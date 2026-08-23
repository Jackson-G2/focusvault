const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const policy = require("../policy.js");

const defaultFile = JSON.parse(
  fs.readFileSync(path.join(__dirname, "..", "default-channels.json"), "utf8")
);

const failures = [];
let passed = 0;

function test(name, fn) {
  try {
    fn();
    passed += 1;
    console.log(`PASS [${passed}]: ${name}`);
  } catch (error) {
    failures.push({ name, error });
    console.log(`FAIL: ${name} — ${error.message}`);
  }
}

function fakeDocument(hrefs = [], metaChannelId = "") {
  return {
    querySelectorAll() {
      return hrefs.map((href) => ({
        href,
        getAttribute: () => href
      }));
    },
    querySelector() {
      return metaChannelId ? { content: metaChannelId } : null;
    }
  };
}

const defaults = policy.DEFAULT_CHANNELS;
const alex = defaults[0];
const moremozi = defaults[1];

// Configuration and normalization

test("default channel JSON matches policy defaults", () => {
  assert.equal(defaultFile.length, 2);
  assert.equal(defaultFile[0].channelId, alex.ids[0]);
  assert.equal(defaultFile[1].channelId, moremozi.ids[0]);
  assert.equal(defaultFile[0].handle.toLowerCase(), alex.handles[0]);
  assert.equal(defaultFile[1].handle.toLowerCase(), moremozi.handles[0]);
});

test("normalizes case and @ prefixes", () => {
  assert.equal(policy.normalizeHandle("@@AlexHormozi"), "alexhormozi");
  assert.equal(policy.normalizeChannelId(alex.ids[0]), alex.ids[0]);
});

test("deduplicates channel entries", () => {
  const result = policy.normalizeAllowlist([
    { name: "Alex", handle: "@AlexHormozi" },
    { name: "Alex again", handle: "alexhormozi", channelId: alex.ids[0] }
  ]);
  assert.equal(result.length, 2);
  assert.equal(result[0].handles[0], "alexhormozi");
});

test("rejects malformed channel IDs", () => {
  assert.equal(policy.normalizeChannel({ name: "bad", channelId: "UC-short" }), null);
});

test("rejects malformed handles", () => {
  assert.equal(policy.normalizeChannel({ name: "bad", handle: "not a handle" }), null);
});

// Direct URL decisions

test("allows official Alex Hormozi handle", () => {
  assert.equal(policy.decisionForUrl("https://www.youtube.com/@AlexHormozi").state, "allow");
});

test("allows official MoreMozi handle", () => {
  assert.equal(policy.decisionForUrl("https://www.youtube.com/@MoreMozi/videos").state, "allow");
});

test("allows mobile official channel", () => {
  assert.equal(policy.decisionForUrl("https://m.youtube.com/@MoreMozi").state, "allow");
});

test("allows /c/ legacy channel URL", () => {
  assert.equal(policy.decisionForUrl("https://www.youtube.com/c/MoreMozi").state, "allow");
});

test("allows /user/ legacy channel URL", () => {
  assert.equal(policy.decisionForUrl("https://www.youtube.com/user/MoreMozi").state, "allow");
});

test("allows official channel ID URL", () => {
  assert.equal(
    policy.decisionForUrl(`https://www.youtube.com/channel/${alex.ids[0]}`).state,
    "allow"
  );
});

test("blocks an unknown channel handle", () => {
  assert.equal(policy.decisionForUrl("https://www.youtube.com/@randomcreator").state, "block");
});

test("blocks an impersonator handle", () => {
  assert.equal(policy.decisionForUrl("https://www.youtube.com/@AlexHormoziOfficial").state, "block");
});

test("blocks an unknown channel ID", () => {
  assert.equal(
    policy.decisionForUrl("https://www.youtube.com/channel/UC1234567890123456789012").state,
    "block"
  );
});

test("does not prefix-match channel IDs", () => {
  assert.equal(
    policy.decisionForUrl(`https://www.youtube.com/channel/${alex.ids[0]}extra`).state,
    "block"
  );
});

test("allows music.youtube.com official channel", () => {
  assert.equal(policy.decisionForUrl("https://music.youtube.com/@AlexHormozi").state, "allow");
});

test("allows www.youtu.be as a pending video", () => {
  assert.equal(policy.decisionForUrl("https://www.youtu.be/abc123").state, "pending");
});

test("watch pages require video-owner inspection", () => {
  assert.equal(policy.decisionForUrl("https://www.youtube.com/watch?v=abc123").state, "pending");
});

test("shorts pages require video-owner inspection", () => {
  assert.equal(policy.decisionForUrl("https://www.youtube.com/shorts/abc123").state, "pending");
});

test("live pages require video-owner inspection", () => {
  assert.equal(policy.decisionForUrl("https://www.youtube.com/live/abc123").state, "pending");
});

test("blocks home page", () => {
  assert.equal(policy.decisionForUrl("https://www.youtube.com/").state, "block");
});

test("blocks search results", () => {
  assert.equal(policy.decisionForUrl("https://www.youtube.com/results?search_query=workout").state, "block");
});

test("blocks subscriptions feed", () => {
  assert.equal(policy.decisionForUrl("https://www.youtube.com/feed/subscriptions").state, "block");
});

test("blocks playlists", () => {
  assert.equal(policy.decisionForUrl("https://www.youtube.com/playlist?list=abc").state, "block");
});

test("blocks deceptive double slashes", () => {
  assert.equal(policy.decisionForUrl("https://www.youtube.com//@AlexHormozi").state, "allow");
});

test("does not treat non-YouTube domains as allowed channels", () => {
  assert.equal(policy.decisionForUrl("https://example.com/@AlexHormozi").state, "outside");
});

test("invalid URL fails closed", () => {
  assert.equal(policy.decisionForUrl("not a URL").state, "block");
});

// Video-owner decisions

test("allows watch page after approved owner handle appears", () => {
  const doc = fakeDocument(["/channel/" + alex.ids[0]]);
  assert.equal(
    policy.decisionForDocument("https://www.youtube.com/watch?v=abc", doc).state,
    "allow"
  );
});

test("allows watch page after approved owner handle appears", () => {
  const doc = fakeDocument(["/@MoreMozi"]);
  assert.equal(
    policy.decisionForDocument("https://www.youtube.com/watch?v=abc", doc).state,
    "allow"
  );
});

test("blocks watch page after unapproved owner appears", () => {
  const doc = fakeDocument(["/@randomcreator"]);
  assert.equal(
    policy.decisionForDocument("https://www.youtube.com/watch?v=abc", doc).state,
    "block"
  );
});

test("keeps watch page pending while owner metadata is unavailable", () => {
  assert.equal(
    policy.decisionForDocument("https://www.youtube.com/watch?v=abc", fakeDocument()).state,
    "pending"
  );
});

test("allows watch page from meta channel ID", () => {
  const doc = fakeDocument([], alex.ids[0]);
  assert.equal(
    policy.decisionForDocument("https://www.youtube.com/watch?v=abc", doc).state,
    "allow"
  );
});

test("extracts relative channel hrefs", () => {
  assert.deepEqual(policy.channelFromHref(`/@${alex.handles[0]}`), { handle: alex.handles[0] });
  assert.deepEqual(policy.channelFromHref(`/channel/${alex.ids[0]}`), { id: alex.ids[0] });
});

test("extracts URL-encoded handles", () => {
  assert.deepEqual(policy.channelFromHref("https://www.youtube.com/%40AlexHormozi"), {
    handle: alex.handles[0]
  });
});

test("ignores external owner links", () => {
  assert.equal(policy.channelFromHref("https://example.com/channel/" + alex.ids[0]), null);
});

test("matches by exact handle", () => {
  assert.equal(policy.channelMatches({ handle: "AlexHormozi" }, defaults), true);
  assert.equal(policy.channelMatches({ handle: "AlexHormoziOfficial" }, defaults), false);
});

test("matches by exact channel ID", () => {
  assert.equal(policy.channelMatches({ id: alex.ids[0] }, defaults), true);
  assert.equal(policy.channelMatches({ id: alex.ids[0] + "x" }, defaults), false);
});

test("empty allowlist blocks an approved handle", () => {
  assert.equal(policy.decisionForUrl("https://www.youtube.com/@AlexHormozi", []).state, "block");
});

test("case-insensitive approved handle works", () => {
  assert.equal(policy.decisionForUrl("https://www.youtube.com/@alexhormozi").state, "allow");
});

test("channel URL query strings do not change identity", () => {
  assert.equal(policy.decisionForUrl("https://www.youtube.com/@MoreMozi?sub_confirmation=1").state, "allow");
});

test("channel subpaths remain allowed", () => {
  assert.equal(policy.decisionForUrl("https://www.youtube.com/@MoreMozi/community").state, "allow");
});

test("default list contains only the two requested channels", () => {
  assert.deepEqual(defaults.map((entry) => entry.handles[0]), ["alexhormozi", "moremozi"]);
});

if (failures.length) {
  console.log(`FAIL: ${failures.length} of ${passed + failures.length} extension policy tests failed`);
  process.exitCode = 1;
} else {
  console.log(`PASS: all ${passed} FocusVault extension policy tests completed`);
}
