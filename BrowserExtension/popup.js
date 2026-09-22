(() => {
  const policy = globalThis.VaultyPolicy;
  const defaults = policy?.DEFAULT_CHANNELS || [];
  const title = document.getElementById("title");
  const statusLine = document.getElementById("status");
  const copy = document.getElementById("copy");
  const list = document.getElementById("channels");
  const action = document.getElementById("session-action");
  let currentStatus = null;
  let refreshTimer = null;

  function formatTime(rawSeconds) {
    const seconds = Math.max(0, Number(rawSeconds) || 0);
    return `${String(Math.floor(seconds / 60)).padStart(2, "0")}:${String(Math.floor(seconds % 60)).padStart(2, "0")}`;
  }

  function setDot(kind) {
    const dot = statusLine.querySelector(".dot");
    dot.className = `dot ${kind || ""}`.trim();
  }

  function renderTimedGate(status) {
    list.hidden = true;
    currentStatus = status;
    action.disabled = false;
    title.textContent = "YouTube gate";

    if (status.locked !== false || Number(status.remainingSeconds) <= 0) {
      statusLine.lastChild.textContent = " Locked";
      setDot("locked");
      copy.textContent = "Unlock in Vaulty with your Mac password, then clear three Signal Shift rooms.";
      action.textContent = "Unlock for 45 minutes";
      return;
    }

    statusLine.lastChild.textContent = ` Open · ${formatTime(status.remainingSeconds)}`;
    setDot("open");
    copy.textContent = "Vaulty will lock every open YouTube tab when this timer reaches zero.";
    action.textContent = "Lock now";
  }

  function renderFallback(channels) {
    currentStatus = null;
    title.textContent = "Channel vault";
    statusLine.lastChild.textContent = " Companion only";
    setDot("");
    copy.textContent = "Finish Vaulty’s one-time guard setup for password-gated 45-minute sessions. Until then, only these channels can open.";
    action.textContent = "Open Vaulty setup";
    action.disabled = false;
    list.hidden = false;
    list.textContent = "";
    for (const channel of channels) {
      const normalized = policy.normalizeChannel(channel);
      if (!normalized) continue;
      const item = document.createElement("li");
      const name = document.createElement("strong");
      name.textContent = normalized.name;
      const handle = document.createElement("span");
      handle.textContent = normalized.handles?.[0] ? `@${normalized.handles[0]}` : "channel ID";
      item.append(name, handle);
      list.appendChild(item);
    }
  }

  function refresh() {
    clearTimeout(refreshTimer);
    chrome.runtime.sendMessage(
      { type: "vaulty-session-status", force: true },
      (status) => {
        if (!chrome.runtime.lastError && status?.installed) {
          renderTimedGate(status);
        } else {
          chrome.storage.sync.get({ allowedChannels: defaults }, (result) => {
            renderFallback(Array.isArray(result.allowedChannels) ? result.allowedChannels : defaults);
          });
        }
        refreshTimer = setTimeout(refresh, 1000);
      }
    );
  }

  action.addEventListener("click", () => {
    if (!currentStatus) {
      window.location.href = "vaulty://unlock-youtube";
      return;
    }

    if (currentStatus.locked !== false || Number(currentStatus.remainingSeconds) <= 0) {
      const url = chrome.runtime.getURL("blocked.html?mode=youtube-session&from=https%3A%2F%2Fwww.youtube.com%2F");
      chrome.tabs.create({ url });
      window.close();
      return;
    }

    action.disabled = true;
    action.textContent = "Locking…";
    chrome.runtime.sendMessage({ type: "vaulty-lock-youtube" }, (status) => {
      if (!chrome.runtime.lastError && status?.ok) {
        renderTimedGate({ ...status, locked: true, remainingSeconds: 0 });
      } else {
        action.disabled = false;
        action.textContent = "Try lock again";
      }
    });
  });

  document.getElementById("options")?.addEventListener("click", () => {
    chrome.runtime.openOptionsPage();
  });

  refresh();
})();
