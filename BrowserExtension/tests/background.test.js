"use strict";
const assert = require("node:assert/strict");
const { background } = require("./browser-fixtures.js");
let passed = 0;
const failures = [];
function test(name, fn) { try { fn(); passed++; console.log("PASS: " + name); } catch (error) { failures.push(name); console.error("FAIL: " + name, error); } }
const open = { ok: true, installed: true, locked: false, unlockUntil: 70_000, remainingSeconds: 999_999 };

test("native status waits for persisted pairing and never downgrades a paired profile", () => {
  const app = background({ paired: true, deferredPairing: true });
  const replies = app.request({ type: "vaulty-session-status", force: true });
  assert.equal(app.ports[0].sent.length, 0);
  app.loadPairing();
  app.ports[0].reply(0, { installed: false, ok: false });
  assert.equal(replies[0].installed, true);
  assert.equal(replies[0].locked, true);
});
test("concurrent forced polls coalesce and remaining time comes from the exact deadline", () => {
  const app = background();
  const one = app.request({ type: "vaulty-session-status", force: true });
  const two = app.request({ type: "vaulty-session-status", force: true });
  assert.equal(app.ports[0].sent.length, 1);
  app.ports[0].reply(0, open);
  assert.equal(one[0].remainingSeconds, 60);
  assert.deepEqual(two, one);
  assert.equal(app.request({ type: "vaulty-session-status" })[0].locked, false);
  assert.equal(app.ports[0].sent.length, 1);
  assert.equal(app.alarms[0].when, 70_000);
});
test("malformed/coerced native replies fail closed", () => {
  for (const override of [{ ok: false }, { locked: "false" }, { unlockUntil: "70000" },
    { unlockUntil: NaN }, { unlockUntil: Infinity }, { unlockUntil: Number.MAX_SAFE_INTEGER + 1 }]) {
    const app = background({ paired: true });
    const replies = app.request({ type: "vaulty-session-status", force: true });
    app.ports[0].reply(0, { ...open, ...override });
    assert.equal(replies[0].locked, true);
    assert.equal(replies[0].ok, false);
  }
});
test("unavailable native host uses reconnect backoff rather than a connect storm", () => {
  const app = background({ paired: true, unavailable: true });
  for (let i = 0; i < 100; i++) app.request({ type: "vaulty-session-status", force: true });
  assert.equal(app.attempts(), 1);
  app.advance(1000);
  app.request({ type: "vaulty-session-status", force: true });
  assert.equal(app.attempts(), 2);
  app.advance(1000);
  app.request({ type: "vaulty-session-status", force: true });
  assert.equal(app.attempts(), 2);
  app.advance(1000);
  app.request({ type: "vaulty-session-status", force: true });
  assert.equal(app.attempts(), 3);
});
test("a stale in-flight status cannot reopen YouTube after a lock", () => {
  const app = background({ paired: true });
  const old = app.request({ type: "vaulty-session-status", force: true });
  const locked = app.request({ type: "vaulty-lock-youtube" });
  const whileLocking = app.request({ type: "vaulty-session-status", force: true });
  assert.equal(whileLocking[0].locked, true);
  app.ports[0].reply(1, { ok: true, installed: true, locked: true });
  app.ports[0].reply(0, open);
  assert.equal(locked[0].locked, true);
  assert.equal(old[0].locked, true);
  assert.equal(app.request({ type: "vaulty-session-status" })[0].locked, true);
});
test("timeouts dispose only the owned port and stale port callbacks cannot corrupt a new connection", () => {
  const app = background({ paired: true });
  const one = app.request({ type: "vaulty-session-status", force: true });
  const two = app.request({ type: "vaulty-session-status", force: true });
  const old = app.ports[0];
  app.timer.fire(2500);
  assert.equal(old.disconnected, true);
  assert.equal(one.length, 1);
  assert.equal(two.length, 1);
  assert.equal(one[0].locked, true);
  app.advance(1000);
  const fresh = app.request({ type: "vaulty-session-status", force: true });
  old.onDisconnect.emit();
  old.reply(0, open);
  app.ports[1].reply(0, open);
  assert.equal(fresh[0].ok, true);
  assert.equal(fresh[0].locked, false);
  assert.equal(one.length, 1);
});
test("browser messages cannot request a privileged unlock", () => {
  const app = background();
  assert.deepEqual(app.request({ type: "vaulty-unlock-youtube" }), []);
  assert.equal(app.ports[0].sent.length, 0);
});
console.log(`Browser native adapter: ${passed} passed, ${failures.length} failed`);
if (failures.length) process.exitCode = 1;
