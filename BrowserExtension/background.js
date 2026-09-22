const DEFAULT_CHANNELS = [
  {
    name: "Alex Hormozi",
    handles: ["alexhormozi"],
    ids: ["UCUyDOdBWhC1MCxEjC46d-zw"]
  },
  {
    name: "MoreMozi",
    handles: ["moremozi"],
    ids: ["UCrvchO1h6lWZAuGaa1LqX9Q"]
  }
];

const NATIVE_HOST = "com.jacksongb.vaulty";
const EXPIRY_ALARM = "vaulty-youtube-expiry";
let nativePort = null;
let nextRequestID = 1;
const pending = new Map();
let cachedStatus = null;
let cachedAt = 0;
let nativeGuardPaired = false;

chrome.storage.local.get({ nativeGuardPaired: false }, (result) => {
  nativeGuardPaired = result.nativeGuardPaired === true;
});

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
    ok: false,
    installed: nativeGuardPaired,
    locked: nativeGuardPaired ? true : null,
    remainingSeconds: 0,
    error: message
  };
}

function connectNativeHost() {
  if (nativePort) return nativePort;
  try {
    nativePort = chrome.runtime.connectNative(NATIVE_HOST);
  } catch (error) {
    nativePort = null;
    return null;
  }

  nativePort.onMessage.addListener((message) => {
    if (!message || !message.id) return;
    const callback = pending.get(message.id);
    if (!callback) return;
    pending.delete(message.id);
    callback(message);
  });

  nativePort.onDisconnect.addListener(() => {
    const detail = chrome.runtime.lastError?.message || "Vaulty native guard disconnected.";
    nativePort = null;
    cachedStatus = null;
    cachedAt = 0;
    for (const callback of pending.values()) {
      callback(unavailableStatus(detail));
    }
    pending.clear();
  });
  return nativePort;
}

function nativeRequest(command, callback) {
  const port = connectNativeHost();
  if (!port) {
    callback(unavailableStatus());
    return;
  }

  const id = `vaulty-${Date.now()}-${nextRequestID++}`;
  const timeout = setTimeout(() => {
    if (!pending.has(id)) return;
    pending.delete(id);
    callback(unavailableStatus("Vaulty native guard timed out."));
  }, 2500);

  pending.set(id, (message) => {
    clearTimeout(timeout);
    callback(message);
  });

  try {
    port.postMessage({ id, command });
  } catch (error) {
    clearTimeout(timeout);
    pending.delete(id);
    nativePort = null;
    callback(unavailableStatus(error.message));
  }
}

function synchronizeExpiryAlarm(status) {
  const deadline = Number(status?.unlockUntil || 0);
  if (status?.installed === true && status.locked === false && deadline > Date.now()) {
    chrome.alarms.create(EXPIRY_ALARM, { when: deadline });
  } else {
    chrome.alarms.clear(EXPIRY_ALARM);
  }
}

function broadcastSessionChanged() {
  chrome.tabs.query(
    { url: ["*://*.youtube.com/*", "*://youtu.be/*"] },
    (tabs) => {
      for (const tab of tabs || []) {
        if (tab.id != null) {
          chrome.tabs.sendMessage(tab.id, { type: "vaulty-session-changed" }, () => {
            void chrome.runtime.lastError;
          });
        }
      }
    }
  );
}

function getSessionStatus(callback, force = false) {
  const now = Date.now();
  if (!force && cachedStatus && now - cachedAt < 300) {
    callback(cachedStatus);
    return;
  }

  nativeRequest("status", (status) => {
    if (status?.installed === true && !nativeGuardPaired) {
      nativeGuardPaired = true;
      chrome.storage.local.set({ nativeGuardPaired: true });
    }
    cachedStatus = status;
    cachedAt = Date.now();
    synchronizeExpiryAlarm(status);
    callback(status);
  });
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type === "vaulty-session-status") {
    getSessionStatus(sendResponse, Boolean(message.force));
    return true;
  }

  if (message?.type === "vaulty-lock-youtube") {
    nativeRequest("lock", (status) => {
      cachedStatus = status?.ok
        ? { ...status, locked: true, remainingSeconds: 0, unlockUntil: null }
        : status;
      cachedAt = Date.now();
      synchronizeExpiryAlarm(cachedStatus);
      broadcastSessionChanged();
      sendResponse(cachedStatus);
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
