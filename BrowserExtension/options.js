(() => {
  const policy = globalThis.FocusVaultPolicy;
  const list = document.getElementById("channel-list");
  const message = document.getElementById("message");

  function lineForChannel(channel) {
    const handle = channel.handles?.[0] ? `@${channel.handles[0]}` : "";
    const id = channel.ids?.[0] || "";
    return [channel.name || handle || id, handle, id].filter(Boolean).join(" | ");
  }

  function load() {
    chrome.storage.sync.get({ allowedChannels: policy.DEFAULT_CHANNELS }, (result) => {
      const channels = policy.normalizeAllowlist(result.allowedChannels);
      list.value = channels.map(lineForChannel).join("\n");
    });
  }

  function parseLines() {
    const errors = [];
    const entries = [];
    list.value.split(/\r?\n/).forEach((rawLine, index) => {
      const line = rawLine.trim();
      if (!line) return;
      const parts = line.split("|").map((part) => part.trim()).filter(Boolean);
      let entry;
      if (parts.length === 1) {
        entry = parts[0].startsWith("UC")
          ? { name: parts[0], channelId: parts[0] }
          : { name: parts[0], handle: parts[0] };
      } else {
        entry = {
          name: parts[0],
          handle: parts[1],
          channelId: parts[2]
        };
      }
      if (!policy.normalizeChannel(entry)) {
        errors.push(`line ${index + 1}`);
      } else {
        entries.push(entry);
      }
    });
    return { entries, errors };
  }

  function save() {
    const parsed = parseLines();
    if (parsed.errors.length) {
      message.textContent = `Invalid ${parsed.errors.join(", ")}. Use a @handle or UC channel ID.`;
      message.className = "message error";
      return;
    }
    if (!parsed.entries.length) {
      message.textContent = "Add at least one allowed channel, or use Reset defaults.";
      message.className = "message error";
      return;
    }
    chrome.storage.sync.set({ allowedChannels: parsed.entries }, () => {
      message.textContent = "Allowlist saved. Your channel vault is active.";
      message.className = "message success";
    });
  }

  function reset() {
    chrome.storage.sync.set({ allowedChannels: policy.DEFAULT_CHANNELS }, load);
    message.textContent = "Defaults restored: Alex Hormozi and MoreMozi.";
    message.className = "message success";
  }

  document.getElementById("save").addEventListener("click", save);
  document.getElementById("reset").addEventListener("click", reset);
  load();
})();
