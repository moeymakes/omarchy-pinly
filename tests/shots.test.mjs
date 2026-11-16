// Run with: node --test tests/*.test.mjs
import { test } from "node:test"
import assert from "node:assert/strict"
import { createRequire } from "node:module"

const require = createRequire(import.meta.url)
const s = require("../shots.js")
const DAY = 86400000
const meta = (hash, path, mtime = 1000, extra = {}) => ({ hash, path, size: 10, mtime, w: 100, h: 50, ...extra })

test("store parsing never treats a damaged file as empty", () => {
  assert.equal(s.parseStore("").ok, false)
  assert.equal(s.parseStore("{").ok, false)
  assert.equal(s.parseStore("[]").ok, false)
  assert.equal(s.parseStore('{"records":{}}').ok, true)
  assert.equal(s.parseStore('{"records":{}}').store.cats.length, 5)
})

test("scan plan: new, changed and unchanged files; missing files are marked gone", () => {
  let { records } = s.upsert({}, [meta("a", "/p/a.png"), meta("b", "/p/b.png"), meta("c", "/p/c.png")])
  const plan = s.planScan(records, [
    { path: "/p/a.png", size: 10, mtime: 1000 },
    { path: "/p/b.png", size: 99, mtime: 1000 },
    { path: "/p/new.png", size: 5, mtime: 2000 },
  ])
  assert.deepEqual(plan.need.map(f => f.path), ["/p/b.png", "/p/new.png"])
  assert.deepEqual(plan.gone, ["c"])
  records = s.markGone(records, plan.gone)
  assert.equal(records.c.gone, true)
  assert.equal(s.select(records, s.defaultCats(), "all", "").length, 2)
})

test("a moved or renamed file keeps its category and favorite", () => {
  let r = s.upsert({}, [meta("a", "/p/a.png")]).records
  r = s.setCat(r, "a", "bugs")
  r = s.setFav(r, "a", true)
  const moved = s.upsert(r, [meta("a", "/q/renamed.png")])
  assert.equal(moved.added, 0)
  assert.equal(moved.records.a.path, "/q/renamed.png")
  assert.equal(moved.records.a.cat, "bugs")
  assert.equal(moved.records.a.fav, true)
})

test("inbox leaves when a category or a favorite is set, and returns when cleared", () => {
  let r = s.upsert({}, [meta("a", "/p/a.png"), meta("b", "/p/b.png")]).records
  const inbox = () => s.select(r, s.defaultCats(), "inbox", "").map(x => x.hash).sort()
  assert.deepEqual(inbox(), ["a", "b"])
  r = s.setCat(r, "a", "design")
  r = s.setFav(r, "b", true)
  assert.deepEqual(inbox(), [])
  r = s.setCat(r, "a", null)
  assert.deepEqual(inbox(), ["a"])
})

test("trash and restore", () => {
  let r = s.upsert({}, [meta("a", "/p/a.png")]).records
  r = s.setTrashed(r, "a", true, 5)
  assert.equal(s.select(r, s.defaultCats(), "all", "").length, 0)
  assert.equal(s.select(r, s.defaultCats(), "trash", "").length, 1)
  assert.equal(s.counts(r, s.defaultCats()).trash, 1)
  r = s.setTrashed(r, "a", false)
  assert.equal(s.select(r, s.defaultCats(), "inbox", "").length, 1)
})

test("search covers file name, app, category name and OCR text, with filters", () => {
  let r = s.upsert({}, [
    meta("a", "/p/screenshot-2026-11-03_08-58-48.png", 3000, { app: "chrome" }),
    meta("b", "/p/screenshot-2026-11-07_22-51-02-helium.png", 2000),
  ]).records
  r = s.setOcr(r, "a", "Invoice 2026 total due")
  r = s.setCat(r, "a", "receipts")
  const cats = s.defaultCats()
  const find = q => s.select(r, cats, "all", q).map(x => x.hash)
  assert.deepEqual(find("invoice due"), ["a"])
  assert.deepEqual(find("receipts"), ["a"])
  assert.deepEqual(find("app:chrome"), ["a"])
  assert.deepEqual(find("app:helium"), ["b"])
  assert.deepEqual(find("cat:rece"), ["a"])
  assert.deepEqual(find("is:unsorted"), ["b"])
  assert.deepEqual(find("nothing like this"), [])
})

test("results are newest first and the old view only holds old unsorted shots", () => {
  const now = 100 * DAY
  let r = s.upsert({}, [meta("old", "/p/o.png", (now - 30 * DAY) / 1000), meta("new", "/p/n.png", (now - 1 * DAY) / 1000), meta("oldsorted", "/p/s.png", (now - 40 * DAY) / 1000)]).records
  r = s.setCat(r, "oldsorted", "chats")
  assert.deepEqual(s.select(r, s.defaultCats(), "all", "", 14, now).map(x => x.hash), ["new", "old", "oldsorted"])
  assert.deepEqual(s.select(r, s.defaultCats(), "old", "", 14, now).map(x => x.hash), ["old"])
  assert.equal(s.counts(r, s.defaultCats(), 14, now).old, 1)
})

test("app comes from the file name when none was recorded", () => {
  assert.equal(s.appFromName("/p/screenshot-2026-11-08_07-06-54-claude-desktop.png"), "claude-desktop")
  assert.equal(s.appFromName("/p/screenshot-2026-11-07_22-51-02-chrome-cacmkiopjkadcibhc.png"), "chrome")
  assert.equal(s.appFromName("/p/screenshot-2026-11-03_08-58-48.png"), "")
})

test("a clipboard image file is matched to its screenshot by content hash", () => {
  const full = "ab".repeat(32)
  const r = s.upsert({}, [meta(full.slice(0, 32), "/p/a.png")]).records
  assert.equal(s.shotForClipboardImage(r, "/home/u/.local/state/omarchy/clipboard-images/" + full + ".png").path, "/p/a.png")
  assert.equal(s.shotForClipboardImage(r, "/x/other.png"), null)
})

test("a gone shot whose file is back is revived, and an empty listing never marks everything gone", () => {
  let r = s.upsert({}, [meta("a", "/p/a.png"), meta("b", "/p/b.png")]).records
  r = s.setCat(r, "a", "bugs")
  assert.deepEqual(s.planScan(r, []).gone, [])
  r = s.markGone(r, ["a", "b"])
  const plan = s.planScan(r, [{ path: "/p/a.png", size: 10, mtime: 1000 }, { path: "/p/b.png", size: 10, mtime: 1000 }])
  assert.deepEqual(plan.need.map(f => f.path).sort(), ["/p/a.png", "/p/b.png"])
  const back = s.upsert(r, [meta("a", "/p/a.png"), meta("b", "/p/b.png")]).records
  assert.equal(back.a.gone, false)
  assert.equal(back.a.cat, "bugs")
})

test("a file edited in place keeps its category and favorite instead of leaving a ghost record", () => {
  let r = s.upsert({}, [meta("old", "/p/x.png")]).records
  r = s.setCat(r, "old", "bugs")
  r = s.setFav(r, "old", true)
  const edited = s.upsert(r, [meta("new", "/p/x.png", 2000)]).records
  assert.equal(edited.old, undefined)
  assert.equal(edited.new.cat, "bugs")
  assert.equal(edited.new.fav, true)
  assert.equal(Object.keys(edited).length, 1)
})

test("a damaged store with records as an array is rejected, and file URLs are encoded", () => {
  assert.equal(s.parseStore('{"records":[]}').ok, false)
  assert.equal(s.fileUrl("/p/a #1?.png"), "file:///p/a%20%231%3F.png")
})
