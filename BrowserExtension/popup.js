(() => {
  const list = document.getElementById("channels");
  const defaults = globalThis.FocusVaultPolicy?.DEFAULT_CHANNELS || [];

  function render(channels) {
    list.textContent = "";
    for (const channel of channels) {
      const item = document.createElement("li");
      const name = document.createElement("strong");
      name.textContent = channel.name;
      const handle = document.createElement("span");
      const firstHandle = channel.handles?.[0] || "channel ID";
      handle.textContent = `@${firstHandle}`;
      item.append(name, handle);
      list.appendChild(item);
    }
  }

  // popup.html does not need policy.js at runtime; these are replaced by storage values.
  chrome.storage.sync.get({ allowedChannels: defaults }, (result) => {
    render(Array.isArray(result.allowedChannels) ? result.allowedChannels : defaults);
  });

  document.getElementById("options")?.addEventListener("click", () => {
    chrome.runtime.openOptionsPage();
  });
})();
