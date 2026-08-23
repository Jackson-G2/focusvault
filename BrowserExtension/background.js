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

chrome.runtime.onInstalled.addListener(() => {
  chrome.storage.sync.get("allowedChannels", (result) => {
    if (!Array.isArray(result.allowedChannels)) {
      chrome.storage.sync.set({ allowedChannels: DEFAULT_CHANNELS });
    }
  });
});
