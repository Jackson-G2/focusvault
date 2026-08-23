(function (root, factory) {
  const api = factory();
  if (typeof module !== "undefined" && module.exports) {
    module.exports = api;
  } else {
    root.FocusVaultPolicy = api;
  }
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

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

  const YOUTUBE_HOSTS = new Set([
    "youtube.com",
    "www.youtube.com",
    "m.youtube.com",
    "music.youtube.com",
    "youtu.be",
    "www.youtu.be"
  ]);

  function unique(values) {
    return [...new Set(values)];
  }

  function normalizeHandle(value) {
    const handle = String(value || "")
      .trim()
      .replace(/^@+/, "")
      .replace(/^\/+|\/+$/g, "")
      .toLowerCase();
    return /^[a-z0-9][a-z0-9._-]{1,49}$/.test(handle) ? handle : "";
  }

  function normalizeChannelId(value) {
    const id = String(value || "").trim();
    return /^UC[A-Za-z0-9_-]{20,}$/.test(id) ? id : "";
  }

  function normalizeChannel(entry) {
    if (!entry || typeof entry !== "object") return null;
    const handles = unique(
      (Array.isArray(entry.handles) ? entry.handles : [entry.handle])
        .map(normalizeHandle)
        .filter(Boolean)
    );
    const ids = unique(
      (Array.isArray(entry.ids) ? entry.ids : [entry.channelId, entry.id])
        .map(normalizeChannelId)
        .filter(Boolean)
    );
    if (!handles.length && !ids.length) return null;
    return {
      name: String(entry.name || handles[0] || ids[0]),
      handles,
      ids
    };
  }

  function normalizeAllowlist(entries) {
    return (Array.isArray(entries) ? entries : [])
      .map(normalizeChannel)
      .filter(Boolean);
  }

  function channelMatches(channel, entries) {
    if (!channel) return false;
    const handle = normalizeHandle(channel.handle);
    const id = normalizeChannelId(channel.id || channel.channelId);
    return normalizeAllowlist(entries).some((entry) =>
      (handle && entry.handles.includes(handle)) ||
      (id && entry.ids.includes(id))
    );
  }

  function decodeSegment(segment) {
    try {
      return decodeURIComponent(segment);
    } catch (_) {
      return segment;
    }
  }

  function channelFromHref(href) {
    if (!href) return null;
    let url;
    try {
      url = new URL(href, "https://www.youtube.com");
    } catch (_) {
      return null;
    }

    const host = url.hostname.toLowerCase();
    if (!YOUTUBE_HOSTS.has(host)) return null;
    const parts = url.pathname
      .split("/")
      .filter(Boolean)
      .map(decodeSegment);
    if (!parts.length) return null;

    const first = parts[0];
    if (first.startsWith("@")) {
      const handle = normalizeHandle(first);
      return handle ? { handle } : null;
    }
    if (first === "channel" && parts[1]) {
      const id = normalizeChannelId(parts[1]);
      return id ? { id } : null;
    }
    if ((first === "c" || first === "user") && parts[1]) {
      const handle = normalizeHandle(parts[1]);
      return handle ? { handle } : null;
    }
    return null;
  }

  function channelFromDocument(documentObject) {
    if (!documentObject || typeof documentObject.querySelectorAll !== "function") {
      return null;
    }

    const selectors = [
      "ytd-watch-metadata a[href]",
      "ytd-video-owner-renderer a[href]",
      "ytd-reel-player-header-renderer a[href]",
      "#owner a[href]",
      "a[href*='/@']",
      "a[href*='/channel/']"
    ];

    for (const selector of selectors) {
      const nodes = documentObject.querySelectorAll(selector) || [];
      for (const node of nodes) {
        const channel = channelFromHref(node.href || node.getAttribute?.("href"));
        if (channel) return channel;
      }
    }

    const metaSelectors = [
      "meta[itemprop='channelId']",
      "meta[name='channelId']"
    ];
    for (const selector of metaSelectors) {
      const node = documentObject.querySelector?.(selector);
      const id = normalizeChannelId(node?.content || node?.getAttribute?.("content"));
      if (id) return { id };
    }

    return null;
  }

  function decisionForUrl(rawUrl, entries = DEFAULT_CHANNELS) {
    let url;
    try {
      url = new URL(rawUrl);
    } catch (_) {
      return { state: "block", reason: "invalid-url" };
    }

    const host = url.hostname.toLowerCase();
    if (!YOUTUBE_HOSTS.has(host)) {
      return { state: "outside" };
    }

    const path = url.pathname.replace(/\/{2,}/g, "/");
    const directChannel = channelFromHref(url.href);
    if (directChannel) {
      return {
        state: channelMatches(directChannel, entries) ? "allow" : "block",
        reason: "channel-url",
        channel: directChannel
      };
    }

    if (
      host === "youtu.be" ||
      host === "www.youtu.be" ||
      path === "/watch" ||
      path.startsWith("/shorts/") ||
      path.startsWith("/live/")
    ) {
      return { state: "pending", reason: "video-owner-required" };
    }

    return { state: "block", reason: "non-channel-page" };
  }

  function decisionForDocument(rawUrl, documentObject, entries = DEFAULT_CHANNELS) {
    const direct = decisionForUrl(rawUrl, entries);
    if (direct.state !== "pending") return direct;

    const channel = channelFromDocument(documentObject);
    if (!channel) return direct;
    return {
      state: channelMatches(channel, entries) ? "allow" : "block",
      reason: "video-owner",
      channel
    };
  }

  return {
    DEFAULT_CHANNELS,
    YOUTUBE_HOSTS,
    normalizeHandle,
    normalizeChannelId,
    normalizeChannel,
    normalizeAllowlist,
    channelMatches,
    channelFromHref,
    channelFromDocument,
    decisionForUrl,
    decisionForDocument
  };
});
