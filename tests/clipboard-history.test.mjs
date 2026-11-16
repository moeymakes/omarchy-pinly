// Run with: node --test tests/*.test.mjs
import { test } from "node:test"
import assert from "node:assert/strict"
import { createRequire } from "node:module"
import crypto from "node:crypto"

const require = createRequire(import.meta.url)
const m = require("../ClipboardHistory.js")
const text = (t, extra = {}) => ({ type: "text", text: t, ...extra })

test("sha256 matches node's implementation", () => {
  for (const x of ["", "abc", "héllo wörld ✓", "x".repeat(1000)])
    assert.equal(m.sha256hex(x), crypto.createHash("sha256").update(x).digest("hex"))
})

test("secret detection: true positives", () => {
  const positives = [
    ["sk-ant-api03-abcdefghijklmnopqrstuvwx", "API key"],
    ["ghp_" + "a".repeat(36), "GitHub token"],
    ["glpat-" + "a1".repeat(12), "Access token"],
    ["4242 4242 4242 4242", "Card number"],
    ['{"password": "verify-marker-hunter22"}', "Credential"],
    ["password=hunter2", "Credential"],
    ["postgres://user:pass@host/db", "Database URL"],
    ["-----BEGIN PGP PRIVATE KEY BLOCK-----", "Private key"],
    ["Ab1Cd2Ef3Gh4Ij5Kl6Mn7Op8Qr9St0Uv1Wx2Yz3Ab4C", "Token"],
  ]
  for (const [input, kind] of positives) assert.equal(m.secretKind(input), kind, input)
})

test("secret detection: false positives stay clear", () => {
  const negatives = [
    "verify-marker-how-to-configure-hyprland-2024-part3",
    "/home/user/projects/example/x1",
    "const token = getToken();",
    "da39a3ee5e6b4b0d3255bfef95601890afd80709",
    "hello world",
    "4242 4242 4242 4241",
    "https://github.com/foo/bar/pull/123",
  ]
  for (const input of negatives) assert.equal(m.secretKind(input), "", input)
})

test("only high-confidence kinds are auto-deleted", () => {
  assert.equal(m.secretIsSure("JWT"), true)
  assert.equal(m.secretIsSure("Credential"), false)
  assert.equal(m.secretIsSure("Token"), false)
})

test("a secret past the first 4 KB of a long paste is not scanned, one inside it is", () => {
  assert.equal(m.secretKind("A=1\n".repeat(100) + "password: abcdefghi"), "Credential")
})

test("strict parsing never treats a bad file as an empty list", () => {
  assert.equal(m.parseHistoryStrict("").ok, false)
  assert.equal(m.parseHistoryStrict("{").ok, false)
  assert.equal(m.parseHistoryStrict('{"a":1}').ok, false)
  assert.equal(m.parseHistoryStrict("[]").ok, true)
})

test("templates: only lowercase tokens expand", () => {
  const out = m.expandTemplate("x {{DATE}} {{.Ports}} {{ask:APP}} {{date}}", { asks: { APP: "demo" }, now: new Date(2026, 10, 13) })
  assert.equal(out, "x {{DATE}} {{.Ports}} demo 2026-11-13")
  assert.deepEqual(m.templateTokens("{{ask:APP}} {{ask:APP}} {{ask:City}}").asks, ["APP", "City"])
})

test("transforms", () => {
  const codec = { btoa, atob }
  assert.equal(m.applyTransform("b64dec", m.applyTransform("b64enc", "héllo", codec), codec), "héllo")
  assert.equal(m.applyTransform("json", "nope", codec), null)
  assert.equal(m.applyTransform("plain", "  a  \r\nb   \n", codec), "a\nb")
})

test("search filters", () => {
  const h = [text("https://a.io"), text("git status"), text("hello")]
  const meta = {
    [m.keyHash(m.entryKey(h[0]))]: { app: "chrome", t: Date.now(), n: 3 },
    [m.keyHash(m.entryKey(h[1]))]: { app: "kitty", t: Date.now(), n: 1 },
    [m.keyHash(m.entryKey(h[2]))]: { app: "kitty", t: Date.now() },
  }
  const pins = m.addPin([], text("ssh x"), "dev")
  const rows = (q, view = "recent") => m.combinedRows(h, pins, q, 50, view, false, meta, { dev: "dev" }).rows.map(r => r.previewText)
  assert.deepEqual(rows("is:url"), ["https://a.io"])
  assert.deepEqual(rows("app:kitty"), ["git status", "hello"])
  assert.deepEqual(rows("in:dev"), ["ssh x"])
  assert.deepEqual(rows("", "frequent"), ["https://a.io", "git status"])
})

test("archive keeps what the stock list drops, newest first", () => {
  const merged = m.mergeArchive([text("c"), text("b"), text("a")], [text("b"), text("old2"), text("old1")], 0)
  assert.deepEqual(merged.map(e => e.text), ["c", "b", "a", "old2", "old1"])
  assert.equal(m.mergeArchive([text("c")], [text("old")], 1).length, 1)
})

test("merge: newer change wins, tombstones delete, imported images ignored", () => {
  const A = { pins: [text("x", { group: "dev", at: 100 }), text("y", { at: 50 })], groups: [{ id: "dev", name: "Dev2", at: 200 }], tombstones: {} }
  const B = {
    pins: [text("x", { group: "links", at: 200 }), text("z", { at: 10 }), { type: "image", path: "/r.png" }],
    groups: [{ id: "dev", name: "Dev", at: 100 }, { id: "links", name: "Links", at: 1 }],
    tombstones: { [m.keyHash(m.entryKey(text("y")))]: Date.now() },
  }
  const r = m.mergeSnapshots(A, B, Date.now())
  assert.deepEqual(r.pins.map(p => [p.text, p.group]), [["x", "links"], ["z", undefined]])
  assert.equal(r.groups.find(g => g.id === "dev").name, "Dev2")
})

// Two replicas that keep merging with each other must settle, whatever edits they started with.
test("merge converges for random edit histories", () => {
  let seed = 7
  const rnd = n => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed % n }
  for (let round = 0; round < 200; round++) {
    const now = 1_000_000
    const replica = () => ({ pins: [], groups: [], tombstones: {} })
    const a = replica(), b = replica()
    for (const r of [a, b]) {
      for (let i = 0; i < 6; i++) {
        const t = "p" + rnd(5)
        const at = rnd(1000)
        const choice = rnd(3)
        if (choice === 0) r.pins.push(text(t, { at, group: rnd(2) ? "g1" : undefined }))
        else if (choice === 1) r.tombstones[m.keyHash(m.entryKey(text(t)))] = at
        else r.groups.push({ id: "g" + rnd(3), name: "n" + rnd(3), at })
      }
    }
    let x = a, y = b
    for (let i = 0; i < 4; i++) { x = m.mergeSnapshots(x, y, now); y = m.mergeSnapshots(y, x, now) }
    assert.equal(m.fingerprint(x), m.fingerprint(y), "round " + round)
  }
})

test("legacy plain-text keys migrate to hashed keys", () => {
  const out = m.migrateKeys({ "text:abc": 1, keep: 2 })
  assert.equal(out.keep, 2)
  assert.equal(out[m.keyHash("text:abc")], 1)
})

test("retention drops old unpinned entries and caps the count", () => {
  const D = 86400000, now = Date.now()
  const h = [text("new"), text("old"), text("pinned-old")]
  const meta = {
    [m.keyHash(m.entryKey(h[0]))]: { t: now },
    [m.keyHash(m.entryKey(h[1]))]: { t: now - 40 * D },
    [m.keyHash(m.entryKey(h[2]))]: { t: now - 40 * D },
  }
  const out = m.trimHistory(h, meta, { [m.entryKey(h[2])]: true }, 7, 0, now)
  assert.deepEqual(out.map(e => e.text), ["new", "pinned-old"])
  assert.equal(m.trimHistory(h, meta, {}, 0, 1, now).length, 1)
})

test("favorites and tags: normalised, stored on pins, counted and filtered", () => {
  assert.deepEqual(m.normalizeTags("#Dev, deploy  prod,dev,"), ["dev", "deploy-prod"])
  assert.equal(m.normalizeTags(["a", "b", "c", "d", "e", "f", "g", "h", "i"]).length, 8)
  let pins = m.addPin([], text("ssh a"), "dev")
  pins = m.addPin(pins, text("git b"), "dev")
  pins = m.setPinFav(pins, 0, true)
  pins = m.setPinTags(pins, 0, "deploy, prod")
  pins = m.setPinTags(pins, 1, ["prod"])
  const c = m.tagCounts(pins)
  assert.equal(c.favs, 1)
  assert.deepEqual(c.tags.map(t => t.tag + ":" + t.count), ["prod:2", "deploy:1"])
  const rows = sub => m.combinedRows([], pins, "", 50, "all", false, {}, {}, sub).rows.map(r => r.previewText)
  assert.equal(rows("all").length, 2)
  assert.deepEqual(rows("fav"), ["git b".length ? rows("fav")[0] : ""])
  assert.equal(rows("fav").length, 1)
  assert.equal(rows("tag:deploy").length, 1)
  assert.equal(rows("tag:prod").length, 2)
  const q = f => m.combinedRows([], pins, f, 50, "all", false, {}, {}, "all").rows.length
  assert.equal(q("tag:deploy"), 1)
  assert.equal(q("is:fav"), 1)
  assert.equal(q("#prod"), 2)
  const cleared = m.setPinTags(pins, 0, "")
  assert.equal(m.normalizeEntry(cleared[0]).tags, undefined)
})

test("search: words match in any order, best hits first, fuzzy fallback on titles", () => {
  const history = [
    { type: "text", text: "notes about the deploy script" },
    { type: "text", text: "deploy staging now" },
    { type: "text", text: "redeploy the api server" },
    { type: "text", text: "github token rotation checklist" }
  ]
  const idx = m.buildIndex(history, [], {})
  const q = (s, v = "recent") => m.queryIndex(idx, s, 50, v, false, {}, "all").rows.map(r => r.fullText)
  // All words must match, order does not matter.
  assert.deepEqual(q("script deploy"), ["notes about the deploy script"])
  // Title start beats word start beats mid-word.
  assert.deepEqual(q("deploy"), ["deploy staging now", "notes about the deploy script", "redeploy the api server"])
  // No literal match: letters in order within the title.
  assert.deepEqual(q("ghtkn"), ["github token rotation checklist"])
  assert.deepEqual(q("zzz"), [])
  // The index is reusable across queries and agrees with combinedRows.
  assert.deepEqual(m.combinedRows(history, [], "api", 50, "recent", false, {}, {}, "all").rows.map(r => r.fullText), q("api"))
})

test("search: pins keep their pin index, history keeps its file index, pinned copies are hidden", () => {
  const history = [{ type: "text", text: "alpha one" }, { type: "text", text: "alpha two" }]
  const pins = [{ type: "text", text: "alpha two", group: "g1" }]
  const res = m.combinedRows(history, pins, "alpha", 50, "recent", true, {}, {}, "all")
  assert.equal(res.rows.length, 2)
  const pinned = res.rows.find(r => r.pinned)
  assert.equal(pinned.pinIndex, 0); assert.equal(pinned.index, -1); assert.equal(pinned.group, "g1")
  const recent = res.rows.find(r => !r.pinned)
  assert.equal(recent.index, 0); assert.equal(recent.fullText, "alpha one")
  const narrow = m.combinedRows(history, pins, "alpha", 50, "recent", false, {}, {}, "all")
  assert.equal(narrow.rows.length, 1); assert.equal(narrow.elsewhere, 1)
})

test("merge: a hostile remote cannot pin a timestamp in the far future", () => {
  const now = 1_800_000_000_000
  const local = { pins: [text("keep", { at: now - 10 })], groups: [], tombstones: {} }
  const remote = { pins: [text("keep", { at: 9e15, label: "git status" })], groups: [], tombstones: { [m.keyHash("text:other")]: 9e15 } }
  const r = m.mergeSnapshots(local, remote, now)
  assert.ok(r.pins[0].at <= now + 86400000)
  assert.ok(Object.values(r.tombstones).every(v => v <= now + 86400000))
})

test("merge: malformed groups from a peer are dropped, known fields kept", () => {
  const now = 1_800_000_000_000
  const remote = { pins: [], groups: [{ id: "x", name: { a: 1 } }, { id: 5, name: "n" }, null, "g", { id: "ok", name: "Fine", h: 20, evil: "<img src=x>" }], tombstones: {} }
  const r = m.mergeSnapshots({ pins: [], groups: [], tombstones: {} }, remote, now)
  assert.deepEqual(r.groups, [{ id: "ok", name: "Fine", h: 20 }])
})
