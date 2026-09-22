(() => {
  const params = new URLSearchParams(location.search);
  const platformNames = {
    tiktok: "TikTok",
    instagram: "Instagram Reels",
    youtube: "YouTube Shorts",
    facebook: "Facebook Reels"
  };
  const platform = platformNames[params.get("platform")];
  const mode = params.get("mode");
  const isShortForm = mode === "short-form" && platform;
  const isYouTubeSession = mode === "youtube-session";
  const eyebrow = document.getElementById("eyebrow");
  const title = document.getElementById("title");
  const copy = document.getElementById("copy");
  const hint = document.getElementById("hint");
  const manage = document.getElementById("manage");
  const sessionStatus = document.getElementById("session-status");
  let pollTimer = null;

  if (isShortForm) {
    document.title = `Vaulty — ${platform} blocked`;
    eyebrow.textContent = `VAULTY · ${platform.toUpperCase()}`;
    title.innerHTML = `${platform} is closed.<br>Vault in.`;
    copy.textContent = `${platform} is a short-form surface. Vaulty blocked it before the content could open.`;
    manage.textContent = "Open channel settings";
    hint.textContent = "The short-form vault covers TikTok, Instagram Reels, YouTube Shorts, and Facebook Reels.";
  } else if (isYouTubeSession) {
    document.title = "Vaulty — YouTube locked";
    eyebrow.textContent = "VAULTY · YOUTUBE LOCKED";
    title.innerHTML = "YouTube is locked.<br>Choose deliberately.";
    copy.textContent = "Unlocking requires your Mac administrator password, then three Signal Shift rooms. A successful session lasts exactly 45 minutes.";
    manage.textContent = "Unlock in Vaulty";
    hint.textContent = "Locking again never asks for a password. Three missed signals means entering your password again.";
    pollSession();
  }

  manage?.addEventListener("click", () => {
    if (isYouTubeSession) {
      window.location.href = "vaulty://unlock-youtube";
      return;
    }
    chrome.runtime.openOptionsPage();
  });

  function pollSession() {
    clearTimeout(pollTimer);
    chrome.runtime.sendMessage(
      { type: "vaulty-session-status", force: true },
      (status) => {
        if (chrome.runtime.lastError || !status?.installed) {
          sessionStatus.textContent = "Finish the one-time guard setup in Vaulty first.";
          sessionStatus.className = "session-status warning";
          pollTimer = setTimeout(pollSession, 1500);
          return;
        }

        if (status.locked === false && Number(status.remainingSeconds) > 0) {
          sessionStatus.textContent = `Open for ${formatTime(status.remainingSeconds)}. Returning to YouTube…`;
          sessionStatus.className = "session-status success";
          const target = safeReturnURL(params.get("from"));
          setTimeout(() => location.replace(target), 250);
          return;
        }

        sessionStatus.textContent = "Locked now · no session time is running.";
        sessionStatus.className = "session-status";
        pollTimer = setTimeout(pollSession, 1000);
      }
    );
  }

  function safeReturnURL(raw) {
    try {
      const url = new URL(raw || "https://www.youtube.com/");
      const host = url.hostname.toLowerCase();
      if (host === "youtube.com" || host.endsWith(".youtube.com") || host === "youtu.be" || host.endsWith(".youtu.be")) {
        return url.href;
      }
    } catch (_) {
      // Use the safe default below.
    }
    return "https://www.youtube.com/";
  }

  function formatTime(rawSeconds) {
    const seconds = Math.max(0, Number(rawSeconds) || 0);
    const minutes = Math.floor(seconds / 60);
    const remainder = Math.floor(seconds % 60);
    return `${String(minutes).padStart(2, "0")}:${String(remainder).padStart(2, "0")}`;
  }
})();
