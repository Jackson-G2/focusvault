"use strict";
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

function event() {
  const listeners = [];
  return { listeners, addListener(fn) { listeners.push(fn); }, emit(...args) { for (const fn of listeners) fn(...args); } };
}
function timers() {
  let next = 1;
  const pending = new Map();
  return {
    pending,
    set(fn, delay) { const id = next++; pending.set(id, { fn, delay }); return id; },
    clear(id) { pending.delete(id); },
    fire(delay) {
      const batch = [...pending].filter(([, value]) => value.delay === delay);
      for (const [id, value] of batch) { if (pending.delete(id)) value.fn(); }
    }
  };
}
function runSource(name, context) {
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, "..", name), "utf8"), context, { filename: name });
}
function background({ paired = false, deferredPairing = false, unavailable = false } = {}) {
  const timer = timers();
  const ports = [];
  const alarms = [];
  let now = 10_000;
  let attempts = 0;
  let loadPairing;
  const runtime = { onInstalled: event(), onStartup: event(), onMessage: event(), lastError: null,
    connectNative() {
      attempts++;
      if (unavailable) throw new Error("fixture unavailable");
      const port = { onMessage: event(), onDisconnect: event(), sent: [], disconnected: false,
        postMessage(message) { this.sent.push(message); },
        disconnect() { this.disconnected = true; this.onDisconnect.emit(); },
        reply(index, values) { this.onMessage.emit({ id: this.sent[index].id, ...values }); } };
      ports.push(port);
      return port;
    }
  };
  const chrome = { runtime,
    storage: {
      local: { get(_defaults, fn) { loadPairing = fn; if (!deferredPairing) fn({ nativeGuardPaired: paired }); }, set() {} },
      sync: { get(_key, fn) { fn({}); }, set() {} }
    },
    tabs: { query(_query, fn) { fn([]); }, sendMessage() {} },
    alarms: { onAlarm: event(), create(name, options) { alarms.push({ name, ...options }); }, clear() {} }
  };
  runSource("background.js", { chrome, Date: { now: () => now }, setTimeout: timer.set, clearTimeout: timer.clear });
  return { ports, timer, alarms, chrome, attempts: () => attempts,
    advance(ms) { now += ms; }, loadPairing() { loadPairing({ nativeGuardPaired: paired }); },
    request(message) { const replies = []; runtime.onMessage.listeners[0](message, {}, value => replies.push(JSON.parse(JSON.stringify(value)))); return replies; }
  };
}

class Element {
  constructor(href = null, parent = null) { this.href = href; this.parent = parent; this.nodeType = 1; this.children = []; this.dataset = {}; this.attributes = new Map(); this.queries = 0; this.writes = 0; if (parent) parent.children.push(this); }
  contains(node) { return node === this || this.children.some(child => child.contains(node)); }
  matches(selector) { return selector === "a[href]" && this.href !== null; }
  closest(selector) {
    if (selector === "a[href]" && this.href !== null) return this;
    if (selector.startsWith("#") && this.id === selector.slice(1)) return this;
    if (selector.includes("data-vaulty") && this.dataset.vaultyShortFormBlocked === "true") return this;
    if (selector.startsWith("article,") && this.isArticle) return this;
    return this.parent?.closest(selector) ?? null;
  }
  querySelectorAll() {
    this.queries++;
    const links = [];
    const visit = node => { for (const child of node.children) { if (child.href !== null) links.push(child); visit(child); } };
    visit(this);
    return links;
  }
  getAttribute(name) { return name === "href" ? this.href : (this.attributes.get(name) ?? null); }
  setAttribute(name, value) { this.writes++; this.attributes.set(name, value); }
  removeAttribute(name) { this.writes++; this.attributes.delete(name); }
}
function content() {
  const timer = timers();
  const root = new Element();
  const click = event();
  const message = event();
  const navigation = new Map();
  const redirects = [];
  let mutations;
  let fullScans = 0;
  const document = { documentElement: root, getElementById() { return null; },
    querySelectorAll() { fullScans++; return root.querySelectorAll(); },
    addEventListener(name, fn) { if (name === "click") click.addListener(fn); }
  };
  const chrome = { runtime: { onMessage: message, getURL: path => "chrome-extension://fixture/" + path },
    storage: { sync: { get(defaults, fn) { fn(defaults); } }, onChanged: event() } };
  class Observer { constructor(fn) { mutations = fn; } observe() {} }
  runSource("content.js", { chrome, document, window: { addEventListener(name, fn) { navigation.set(name, fn); } },
    location: { href: "https://example.org/", replace(url) { redirects.push(url); } },
    VaultyPolicy: require("../policy.js"), VaultySessionPolicy: require("../session-policy.js"),
    MutationObserver: Observer, URL, URLSearchParams, Date, setTimeout: timer.set, clearTimeout: timer.clear });
  return { root, timer, redirects, click, navigation, fullScans: () => fullScans, mutate: records => mutations(records) };
}
module.exports = { background, content, Element };
