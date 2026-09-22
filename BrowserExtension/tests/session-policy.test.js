const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const sessionPolicy = require("../session-policy.js");

const manifest = JSON.parse(
  fs.readFileSync(path.join(__dirname, "..", "manifest.json"), "utf8")
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

const now = 1_000_000;

test("manifest pins the native-messaging extension identity", () => {
  const digest = crypto.createHash("sha256").update(Buffer.from(manifest.key, "base64")).digest().subarray(0, 16);
  const extensionID = [...digest]
    .map((byte) => String.fromCharCode(97 + (byte >> 4), 97 + (byte & 15)))
    .join("");
  assert.equal(extensionID, "apgojdoelgpjfpmiohffnbkfcbjhjhob");
  assert.ok(manifest.permissions.includes("nativeMessaging"));
  assert.ok(manifest.permissions.includes("alarms"));
  assert.ok(manifest.permissions.includes("tabs"));
});

test("manifest loads session policy before the content enforcer", () => {
  const scripts = manifest.content_scripts[0].js;
  assert.ok(scripts.includes("session-policy.js"));
  assert.ok(scripts.indexOf("session-policy.js") < scripts.indexOf("content.js"));
});

test("uses channel fallback when native guard is missing", () => {
  assert.equal(sessionPolicy.decisionForStatus(null, now).state, "fallback");
  assert.equal(
    sessionPolicy.decisionForStatus({ installed: false, locked: true }, now).state,
    "fallback"
  );
});

test("blocks an explicitly locked native session", () => {
  assert.deepEqual(
    sessionPolicy.decisionForStatus(
      { installed: true, locked: true, unlockUntil: now + 60_000 },
      now
    ),
    { state: "block", reason: "youtube-session-locked" }
  );
});

test("blocks an unlocked state with no deadline", () => {
  assert.equal(
    sessionPolicy.decisionForStatus({ installed: true, locked: false }, now).state,
    "block"
  );
});

test("allows only before the fixed deadline", () => {
  const result = sessionPolicy.decisionForStatus(
    { installed: true, locked: false, unlockUntil: now + 2_700_000 },
    now
  );
  assert.equal(result.state, "allow");
  assert.equal(result.unlockUntil, now + 2_700_000);
  assert.equal(result.remainingMilliseconds, 2_700_000);
});

test("blocks at the exact deadline", () => {
  assert.equal(
    sessionPolicy.decisionForStatus(
      { installed: true, locked: false, unlockUntil: now },
      now
    ).state,
    "block"
  );
});

test("blocks after the deadline", () => {
  assert.equal(
    sessionPolicy.decisionForStatus(
      { installed: true, locked: false, unlockUntil: now - 1 },
      now
    ).state,
    "block"
  );
});

test("manual lock dominates a future deadline", () => {
  assert.equal(
    sessionPolicy.decisionForStatus(
      { installed: true, locked: true, unlockUntil: now + 2_700_000 },
      now
    ).state,
    "block"
  );
});

if (failures.length) {
  console.log(`FAIL: ${failures.length} of ${passed + failures.length} session policy tests failed`);
  process.exitCode = 1;
} else {
  console.log(`PASS: all ${passed} timed YouTube session policy tests completed`);
}
