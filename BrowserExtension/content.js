(() => {
  "use strict";

  const policy = globalThis.VaultyPolicy;
  const sessionPolicy = globalThis.VaultySessionPolicy;
  const DEFAULTS = policy.DEFAULT_CHANNELS;
  const GUARD_ID = "vaulty-channel-guard";
  let allowedChannels = DEFAULTS;
  let evaluationToken = 0;
  let retryTimer = null;
  let sessionExpiryTimer = null;
  let sessionPollTimer = null;

  function showGuard(message) {
    let guard = document.getElementById(GUARD_ID);
    if (!guard) {
      guard = document.createElement("div");
      guard.id = GUARD_ID;
      guard.innerHTML = `
        <div class="vaulty-guard-card">
          <div class="vaulty-guard-mark">✦</div>
          <div class="vaulty-guard-title">Vaulty is checking this page</div>
          <div class="vaulty-guard-copy"></div>
        </div>`;
      const mount = document.documentElement || document.body;
      if (!mount) return;
      mount.appendChild(guard);
    }
    const copy = guard.querySelector(".vaulty-guard-copy");
    if (copy) copy.textContent = message;
  }

  function hideGuard() {
    document.getElementById(GUARD_ID)?.remove();
  }

  function clearEvaluationTimers() {
    if (retryTimer) clearTimeout(retryTimer);
    if (sessionExpiryTimer) clearTimeout(sessionExpiryTimer);
    if (sessionPollTimer) clearTimeout(sessionPollTimer);
    retryTimer = null;
    sessionExpiryTimer = null;
    sessionPollTimer = null;
  }

  function blockPage(decision = {}) {
    const params = new URLSearchParams({ from: location.href });
    if (decision.platform) {
      params.set("platform", decision.platform);
      params.set("mode", "short-form");
    } else if (decision.reason === "youtube-session-locked") {
      params.set("mode", "youtube-session");
    }
    if (decision.reason) params.set("reason", decision.reason);

    const target = chrome.runtime.getURL(`blocked.html?${params.toString()}`);
    if (location.href !== target) location.replace(target);
  }

  function finish(decision, token) {
    if (token !== evaluationToken) return;
    if (["allow", "outside", "not-short-form"].includes(decision.state)) {
      hideGuard();
    } else if (decision.state === "block") {
      hideGuard();
      blockPage(decision);
    }
  }

  function shortFormLinkContainer(anchor) {
    return anchor.closest(
      "article, [role='article'], ytd-rich-item-renderer, ytd-video-renderer, " +
      "ytd-reel-item-renderer, div[data-e2e='scroll-item'], div[data-e2e='recommendation-item']"
    ) || anchor;
  }

  function scanShortFormLinks() {
    if (typeof document.querySelectorAll !== "function") return;
    for (const anchor of document.querySelectorAll("a[href]")) {
      const decision = policy.decisionForShortFormUrl(
        anchor.href || anchor.getAttribute("href")
      );
      if (decision.state !== "block") continue;

      const container = shortFormLinkContainer(anchor);
      container.dataset.vaultyShortFormBlocked = "true";
      container.setAttribute("aria-label", `${decision.platformName || "Short-form content"} blocked by Vaulty`);
    }
  }

  function interceptShortFormNavigation(event) {
    const target = event.target;
    if (!target || typeof target.closest !== "function") return;
    const anchor = target.closest("a[href]");
    if (!anchor) return;

    const decision = policy.decisionForShortFormUrl(
      anchor.href || anchor.getAttribute("href")
    );
    if (decision.state !== "block") return;

    event.preventDefault();
    event.stopImmediatePropagation();
    blockPage(decision);
  }

  function isYouTubePage(rawUrl) {
    try {
      return policy.YOUTUBE_HOSTS.has(new URL(rawUrl).hostname.toLowerCase());
    } catch (_) {
      return false;
    }
  }

  function evaluateChannelFallback(token) {
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
      scanShortFormLinks();
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

  function armSessionMonitoring(status, token) {
    const unlockUntil = Number(status.unlockUntil || 0);
    const remaining = Math.max(0, unlockUntil - Date.now());
    if (remaining <= 0) {
      finish({ state: "block", reason: "youtube-session-locked" }, token);
      return;
    }

    hideGuard();
    sessionExpiryTimer = setTimeout(
      () => evaluate(),
      Math.min(remaining + 25, 2_147_000_000)
    );
    sessionPollTimer = setTimeout(() => evaluate(), 1000);
  }

  function evaluate() {
    const token = ++evaluationToken;
    clearEvaluationTimers();

    const shortFormDecision = policy.decisionForShortFormUrl(location.href);
    if (shortFormDecision.state === "block") {
      finish(shortFormDecision, token);
      return;
    }
    scanShortFormLinks();

    if (!isYouTubePage(location.href)) {
      finish({ state: "outside" }, token);
      return;
    }

    showGuard("Checking the 45-minute YouTube gate…");
    chrome.runtime.sendMessage(
      { type: "vaulty-session-status", force: true },
      (status) => {
        if (token !== evaluationToken) return;
        const sessionDecision = sessionPolicy.decisionForStatus(
          chrome.runtime.lastError ? null : status,
          Date.now()
        );
        if (sessionDecision.state === "fallback") {
          evaluateChannelFallback(token);
          return;
        }
        if (sessionDecision.state === "block") {
          finish({ state: "block", reason: sessionDecision.reason }, token);
          return;
        }
        armSessionMonitoring(
          { ...status, unlockUntil: sessionDecision.unlockUntil },
          token
        );
      }
    );
  }

  function loadSettings() {
    const immediateShortFormDecision = policy.decisionForShortFormUrl(location.href);
    if (immediateShortFormDecision.state === "block") {
      finish(immediateShortFormDecision, ++evaluationToken);
      return;
    }

    if (isYouTubePage(location.href)) {
      showGuard("Checking the 45-minute YouTube gate…");
    }
    chrome.storage.sync.get({ allowedChannels: DEFAULTS }, (result) => {
      allowedChannels = policy.normalizeAllowlist(result.allowedChannels);
      evaluate();
    });
  }

  document.addEventListener("click", interceptShortFormNavigation, true);
  chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== "sync" || !changes.allowedChannels) return;
    allowedChannels = policy.normalizeAllowlist(changes.allowedChannels.newValue);
    evaluate();
  });
  chrome.runtime.onMessage.addListener((message) => {
    if (message?.type === "vaulty-session-changed") {
      evaluate();
    }
  });

  window.addEventListener("yt-navigate-finish", evaluate);
  window.addEventListener("popstate", evaluate);
  window.addEventListener("hashchange", evaluate);

  if (typeof MutationObserver !== "undefined") {
    const observer = new MutationObserver(() => scanShortFormLinks());
    const root = document.documentElement || document;
    observer.observe(root, { childList: true, subtree: true });
  }

  loadSettings();
})();
