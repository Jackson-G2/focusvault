(function (root, factory) {
  const api = factory();
  if (typeof module !== "undefined" && module.exports) {
    module.exports = api;
  } else {
    root.VaultySessionPolicy = api;
  }
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  function decisionForStatus(status, now = Date.now()) {
    if (!status || status.installed !== true) {
      return { state: "fallback", reason: "native-guard-unavailable" };
    }

    const unlockUntil = Number(status.unlockUntil || 0);
    if (status.locked !== false || unlockUntil <= now) {
      return { state: "block", reason: "youtube-session-locked" };
    }

    return {
      state: "allow",
      reason: "active-youtube-session",
      unlockUntil,
      remainingMilliseconds: Math.max(0, unlockUntil - now)
    };
  }

  return { decisionForStatus };
});
