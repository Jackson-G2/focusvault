(() => {
  "use strict";

  const policy = globalThis.FocusVaultPolicy;
  const DEFAULTS = policy.DEFAULT_CHANNELS;
  const GUARD_ID = "focusvault-channel-guard";
  let allowedChannels = DEFAULTS;
  let evaluationToken = 0;
  let retryTimer = null;

  function showGuard(message) {
    let guard = document.getElementById(GUARD_ID);
    if (!guard) {
      guard = document.createElement("div");
      guard.id = GUARD_ID;
      guard.innerHTML = `
        <div class="focusvault-guard-card">
          <div class="focusvault-guard-mark">✦</div>
          <div class="focusvault-guard-title">FocusVault is checking this video</div>
          <div class="focusvault-guard-copy"></div>
        </div>`;
      (document.documentElement || document.body).appendChild(guard);
    }
    const copy = guard.querySelector(".focusvault-guard-copy");
    if (copy) copy.textContent = message;
  }

  function hideGuard() {
    document.getElementById(GUARD_ID)?.remove();
  }

  function blockPage() {
    const target = chrome.runtime.getURL(
      `blocked.html?from=${encodeURIComponent(location.href)}`
    );
    if (location.href !== target) location.replace(target);
  }

  function finish(decision, token) {
    if (token !== evaluationToken) return;
    if (decision.state === "allow" || decision.state === "outside") {
      hideGuard();
    } else if (decision.state === "block") {
      hideGuard();
      blockPage();
    }
  }

  function evaluate() {
    const token = ++evaluationToken;
    if (retryTimer) {
      clearTimeout(retryTimer);
      retryTimer = null;
    }

    const immediate = policy.decisionForDocument(
      location.href,
      document,
      allowedChannels
    );
    if (immediate.state !== "pending") {
      finish(immediate, token);
      return;
    }

    showGuard("Only your allowed channels can open. Checking the video owner…");
    const deadline = Date.now() + 4500;

    const retry = () => {
      if (token !== evaluationToken) return;
      const decision = policy.decisionForDocument(
        location.href,
        document,
        allowedChannels
      );
      if (decision.state !== "pending" || Date.now() >= deadline) {
        finish(
          decision.state === "pending"
            ? { state: "block", reason: "video-owner-not-found" }
            : decision,
          token
        );
        return;
      }
      retryTimer = setTimeout(retry, 150);
    };

    retryTimer = setTimeout(retry, 50);
  }

  function loadSettings() {
    chrome.storage.sync.get({ allowedChannels: DEFAULTS }, (result) => {
      allowedChannels = policy.normalizeAllowlist(result.allowedChannels);
      evaluate();
    });
  }

  chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== "sync" || !changes.allowedChannels) return;
    allowedChannels = policy.normalizeAllowlist(changes.allowedChannels.newValue);
    evaluate();
  });

  window.addEventListener("yt-navigate-finish", evaluate);
  window.addEventListener("popstate", evaluate);
  window.addEventListener("hashchange", evaluate);

  loadSettings();
})();
