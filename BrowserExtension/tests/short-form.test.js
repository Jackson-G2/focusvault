const assert = require("node:assert/strict");
const policy = require("../policy.js");

const cases = [
  {
    name: "TikTok video",
    url: "https://www.tiktok.com/@creator/video/123456789",
    platform: "tiktok"
  },
  {
    name: "Instagram Reel",
    url: "https://www.instagram.com/reel/C0ffee123/",
    platform: "instagram"
  },
  {
    name: "Instagram story",
    url: "https://m.instagram.com/stories/creator/123/",
    platform: "instagram"
  },
  {
    name: "YouTube Short",
    url: "https://www.youtube.com/shorts/abc123",
    platform: "youtube"
  },
  {
    name: "Facebook Reel",
    url: "https://www.facebook.com/reels/videos/123456789",
    platform: "facebook"
  },
  {
    name: "Facebook mobile Reel",
    url: "https://m.facebook.com/reel/123456789",
    platform: "facebook"
  },
  {
    name: "Facebook short link",
    url: "https://fb.watch/abc123/",
    platform: "facebook"
  }
];

let passed = 0;
for (const testCase of cases) {
  const decision = policy.decisionForShortFormUrl(testCase.url);
  assert.equal(decision.state, "block", `${testCase.name} was not blocked`);
  assert.equal(decision.platform, testCase.platform, `${testCase.name} platform mismatch`);
  assert.equal(policy.isShortFormBlockedUrl(testCase.url), true, `${testCase.name} was not recognized`);
  console.log(`PASS [${++passed}]: ${testCase.name}`);
}

const safeRoutes = [
  ["https://www.instagram.com/p/long-form-photo/", "not-short-form"],
  ["https://www.youtube.com/watch?v=long-form-video", "not-short-form"],
  ["https://www.facebook.com/groups/focus", "not-short-form"],
  ["https://example.com/reel/123", "outside"]
];

for (const [url, expectedState] of safeRoutes) {
  assert.equal(
    policy.decisionForShortFormUrl(url).state,
    expectedState,
    `unexpected short-form decision for ${url}`
  );
  console.log(`PASS [${++passed}]: safe/non-supported route ${url}`);
}

assert.equal(policy.decisionForShortFormUrl("not a URL").state, "block");
console.log(`PASS [${++passed}]: invalid short-form URL fails closed`);
console.log(`PASS: all ${passed} short-form platform policy tests completed`);
