"use strict";
const assert = require("node:assert/strict");
const { content, Element } = require("./browser-fixtures.js");
let passed = 0;
const failures = [];
function test(name, fn) { try { fn(); passed++; console.log("PASS: " + name); } catch (error) { failures.push(name); console.error("FAIL: " + name, error); } }
const shorts = "https://www.youtube.com/shorts/fixture1234";
const longForm = "https://www.youtube.com/watch?v=fixture1234";
function added(app, ...nodes) { app.mutate([{ type: "childList", addedNodes: nodes }]); app.timer.fire(50); }

test("navigation and irrelevant mutations never rescan the full page", () => {
  const app = content();
  assert.equal(app.fullScans(), 1);
  for (let i = 0; i < 100; i++) app.navigation.get("yt-navigate-finish")();
  app.mutate([{ type: "childList", addedNodes: [{ nodeType: 3 }], removedNodes: [] }]);
  app.timer.fire(50);
  assert.equal(app.fullScans(), 1);
  assert.equal(app.timer.pending.size, 0);
});
test("nested added roots are deduplicated and marking is idempotent", () => {
  const app = content();
  const subtree = new Element(null, app.root);
  const nested = new Element(null, subtree);
  const link = new Element(shorts, nested);
  added(app, subtree, nested, link);
  assert.equal(subtree.queries, 1);
  assert.equal(nested.queries, 0);
  assert.equal(link.dataset.vaultyShortFormBlocked, "true");
  assert.equal(link.writes, 1);
  added(app, subtree);
  assert.equal(link.writes, 1);
  assert.equal(app.fullScans(), 1);
});
test("changed hrefs restore reused long-form nodes and their original accessibility label", () => {
  const app = content();
  const link = new Element(shorts, app.root);
  link.setAttribute("aria-label", "Original label");
  added(app, link);
  link.href = longForm;
  app.mutate([{ type: "attributes", target: link, attributeName: "href" }]);
  app.timer.fire(50);
  assert.equal(link.dataset.vaultyShortFormBlocked, undefined);
  assert.equal(link.getAttribute("aria-label"), "Original label");
  assert.equal(app.fullScans(), 1);
});
test("a shared container stays blocked while any short-form link remains", () => {
  const app = content();
  const article = new Element(null, app.root);
  article.isArticle = true;
  const one = new Element(shorts, article);
  const two = new Element(shorts, article);
  added(app, article);
  one.href = longForm;
  app.mutate([{ type: "attributes", target: one }]); app.timer.fire(50);
  assert.equal(article.dataset.vaultyShortFormBlocked, "true");
  two.href = longForm;
  app.mutate([{ type: "attributes", target: two }]); app.timer.fire(50);
  assert.equal(article.dataset.vaultyShortFormBlocked, undefined);
  assert.equal(article.getAttribute("aria-label"), null);
});
test("removing a blocked link reevaluates only its previously marked container", () => {
  const app = content();
  const article = new Element(null, app.root); article.isArticle = true;
  const link = new Element(shorts, article);
  added(app, article);
  article.children = [];
  app.mutate([{ type: "childList", target: article, removedNodes: [link], addedNodes: [] }]);
  app.timer.fire(50);
  assert.equal(article.dataset.vaultyShortFormBlocked, undefined);
  assert.equal(app.fullScans(), 1);
});
test("large mutation bursts are bounded and the extension's own guard is ignored", () => {
  const app = content();
  const nodes = Array.from({ length: 250 }, () => new Element(shorts, app.root));
  added(app, ...nodes);
  assert.ok(nodes.every(node => node.dataset.vaultyShortFormBlocked === "true"));
  assert.equal(app.timer.pending.size, 0);
  const guard = new Element(null, app.root); guard.id = "vaulty-channel-guard";
  const child = new Element(shorts, guard);
  added(app, child);
  assert.equal(child.dataset.vaultyShortFormBlocked, undefined);
  assert.equal(app.fullScans(), 1);
});
test("direct short-form clicks are intercepted without native privilege calls", () => {
  const app = content();
  let prevented = 0;
  app.click.emit({ target: new Element(shorts), preventDefault() { prevented++; }, stopImmediatePropagation() { prevented++; } });
  assert.equal(prevented, 2);
  assert.equal(app.redirects.length, 1);
  assert.ok(app.redirects[0].startsWith("chrome-extension://fixture/blocked.html?"));
});
console.log(`Browser DOM adapter: ${passed} passed, ${failures.length} failed`);
if (failures.length) process.exitCode = 1;
