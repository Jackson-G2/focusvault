const DEFAULT_CHANNELS = [
  { name: "Alex Hormozi", handles: ["alexhormozi"], ids: ["UCUyDOdBWhC1MCxEjC46d-zw"] },
  { name: "MoreMozi", handles: ["moremozi"], ids: ["UCrvchO1h6lWZAuGaa1LqX9Q"] }
];

const NATIVE_HOST = "com.jacksongb.vaulty";
const EXPIRY_ALARM = "vaulty-youtube-expiry";
let nativePort = null;
let nextRequestID = 1;
const pending = new Map();
let cachedStatus = null;
let cachedAt = 0;
let nativeGuardPaired = false;
let pairingReady = false;
const pairingWaiters = [];
let nextNativeAttemptAt = 0;
let reconnectDelay = 1000;
let statusWaiters = null;
let statusGeneration = 0;
let locksPending = 0;

chrome.storage.local.get({ nativeGuardPaired: false }, (result) => {
  nativeGuardPaired = nativeGuardPaired || result.nativeGuardPaired === true;
  pairingReady = true;
  for (const callback of pairingWaiters.splice(0)) callback();
});

function afterPairingLoaded(callback) {
  if (pairingReady) callback();
  else pairingWaiters.push(callback);
}

chrome.runtime.onInstalled.addListener(() => {
  chrome.storage.sync.get("allowedChannels", (result) => {
    if (!Array.isArray(result.allowedChannels)) {
      chrome.storage.sync.set({ allowedChannels: DEFAULT_CHANNELS });
    }
  });
  connectNativeHost();
});
chrome.runtime.onStartup.addListener(connectNativeHost);

function unavailableStatus(message = "Vaulty native guard is unavailable.") {
  return {
    ok: false, installed: nativeGuardPaired, locked: nativeGuardPaired ? true : null,
    remainingSeconds: 0, unlockUntil: null, error: message
  };
}

function deferNativeRetry() {
  nextNativeAttemptAt = Date.now() + reconnectDelay;
  reconnectDelay = Math.min(reconnectDelay * 2, 30_000);
}

function failNativePort(port, detail) {
  // A late event from a disposed port must not invalidate a newer connection.
  if (nativePort !== port) return;
  nativePort = null;
  deferNativeRetry();
  cachedStatus = null;
  cachedAt = 0;
  const callbacks = [...pending.values()];
  pending.clear();
  try { port.disconnect(); } catch (_) { /* Already disconnected. */ }
  for (const callback of callbacks) callback(unavailableStatus(detail));
  if (nativeGuardPaired) broadcastSessionChanged();
}

function connectNativeHost() {
  if (nativePort) return nativePort;
  if (Date.now() < nextNativeAttemptAt) return null;
  try {
    nativePort = chrome.runtime.connectNative(NATIVE_HOST);
  } catch (_) {
    deferNativeRetry();
    return null;
  }
  const port = nativePort;
  port.onMessage.addListener((message) => {
    if (nativePort !== port || typeof message?.id !== "string") return;
    const callback = pending.get(message.id);
    if (!callback) return;
    pending.delete(message.id);
    callback(message);
  });
  port.onDisconnect.addListener(() => {
    const detail = chrome.runtime.lastError?.message || "Vaulty native guard disconnected.";
    failNativePort(port, detail);
  });
  return port;
}

function nativeRequest(command, callback) {
  if (command !== "status" && command !== "lock") {
    callback(unavailableStatus("Unsupported native command."));
    return;
  }
  const port = connectNativeHost();
  if (!port) {
    callback(unavailableStatus());
    return;
  }
  const id = `vaulty-${Date.now()}-${nextRequestID++}`;
  const timeout = setTimeout(() => {
    if (pending.has(id)) failNativePort(port, "Vaulty native guard timed out.");
  }, 2500);
  pending.set(id, (message) => {
    clearTimeout(timeout);
    callback(message);
  });
  try {
    port.postMessage({ id, command });
  } catch (error) {
    failNativePort(port, error.message);
  }
}

function validatedStatus(status) {
  if (!status || typeof status.installed !== "boolean") return unavailableStatus("Invalid native status.");
  if (!status.installed) {
    // Never downgrade a paired profile to the permissive channel fallback.
    return unavailableStatus(status.error || "Vaulty native guard is not installed.");
  }
  if (status.ok !== true || typeof status.locked !== "boolean" ||
      (!status.locked && !Number.isSafeInteger(status.unlockUntil))) {
    return unavailableStatus("Invalid native status.");
  }
  if (!nativeGuardPaired) {
    nativeGuardPaired = true;
    chrome.storage.local.set({ nativeGuardPaired: true });
  }
  reconnectDelay = 1000;
  nextNativeAttemptAt = 0;
  const locked = status.locked || status.unlockUntil <= Date.now();
  return {
    ok: true, installed: true, locked,
    unlockUntil: locked ? null : status.unlockUntil,
    remainingSeconds: locked ? 0 : Math.max(0, Math.ceil((status.unlockUntil - Date.now()) / 1000)),
    error: typeof status.error === "string" ? status.error : null
  };
}

function synchronizeExpiryAlarm(status) {
  const deadline = status?.unlockUntil;
  if (status?.ok === true && status.installed === true && status.locked === false &&
      Number.isSafeInteger(deadline) && deadline > Date.now()) {
    chrome.alarms.create(EXPIRY_ALARM, { when: deadline });
  } else {
    chrome.alarms.clear(EXPIRY_ALARM);
  }
}

function broadcastSessionChanged() {
  chrome.tabs.query({ url: ["*://*.youtube.com/*", "*://youtu.be/*"] }, (tabs) => {
    for (const tab of tabs || []) {
      if (tab.id != null) {
        chrome.tabs.sendMessage(tab.id, { type: "vaulty-session-changed" }, () => {
          void chrome.runtime.lastError;
        });
      }
    }
  });
}

function getSessionStatus(callback, force = false) {
  if (!pairingReady) {
    afterPairingLoaded(() => getSessionStatus(callback, force));
    return;
  }
  if (locksPending) {
    callback(unavailableStatus("YouTube is being locked."));
    return;
  }
  if (!force && cachedStatus && Date.now() - cachedAt < 300) {
    callback(cachedStatus);
    return;
  }
  // Concurrent tab/popup polls share one native request, including forced polls.
  if (statusWaiters) {
    statusWaiters.push(callback);
    return;
  }
  statusWaiters = [callback];
  const generation = statusGeneration;
  nativeRequest("status", (rawStatus) => {
    const status = generation === statusGeneration
      ? validatedStatus(rawStatus) : unavailableStatus("Native state changed during this request.");
    if (generation === statusGeneration) {
      cachedStatus = status;
      cachedAt = Date.now();
      synchronizeExpiryAlarm(status);
    }
    const callbacks = statusWaiters;
    statusWaiters = null;
    for (const waiter of callbacks) waiter(status);
  });
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type === "vaulty-session-status") {
    getSessionStatus(sendResponse, message.force === true);
    return true;
  }
  if (message?.type === "vaulty-lock-youtube") {
    afterPairingLoaded(() => {
      locksPending += 1;
      statusGeneration += 1;
      nativeRequest("lock", (rawStatus) => {
        locksPending -= 1;
        statusGeneration += 1;
        const status = validatedStatus(rawStatus);
        cachedStatus = status.ok === true
          ? { ...status, locked: true, remainingSeconds: 0, unlockUntil: null } : status;
        cachedAt = Date.now();
        synchronizeExpiryAlarm(cachedStatus);
        broadcastSessionChanged();
        sendResponse(cachedStatus);
      });
    });
    return true;
  }
  return false;
});

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name !== EXPIRY_ALARM) return;
  cachedStatus = null;
  cachedAt = 0;
  getSessionStatus(() => broadcastSessionChanged(), true);
});
connectNativeHost();
