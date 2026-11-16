// Pure logic for the Screenshots tab: no file or UI access, so it can be tested in node.

function defaultCats() {
  return [
    { id: "bugs", name: "Bugs", h: 10, at: 0 },
    { id: "design", name: "Design refs", h: 280, at: 0 },
    { id: "receipts", name: "Receipts", h: 50, at: 0 },
    { id: "chats", name: "Chats", h: 150, at: 0 },
    { id: "ideas", name: "Ideas", h: 220, at: 0 }
  ]
}

function emptyStore() { return { version: 1, cats: defaultCats(), records: {} } }

// Strict: a missing or damaged file is reported, never silently treated as empty.
function parseStore(raw) {
  var text = String(raw == null ? "" : raw).trim()
  if (!text) return { ok: false, store: emptyStore() }
  try {
    var p = JSON.parse(text)
    if (!p || typeof p !== "object" || Array.isArray(p) || typeof p.records !== "object" || p.records === null || Array.isArray(p.records)) return { ok: false, store: emptyStore() }
    return { ok: true, store: { version: 1, cats: Array.isArray(p.cats) ? p.cats : defaultCats(), records: p.records } }
  } catch (e) {
    return { ok: false, store: emptyStore() }
  }
}

function baseName(path) {
  var parts = String(path || "").split("/")
  return parts[parts.length - 1]
}

// ---- finding files ---------------------------------------------------------
// `found` is [{path, size, mtime}] from the scan. Returns which paths need hashing,
// and which known, non-trashed records no longer have a file.
function planScan(records, found) {
  var byPath = {}
  for (var h in records) if (records[h].path && !records[h].trashed) byPath[records[h].path] = h
  var seen = {}
  var need = []
  for (var i = 0; i < found.length; i++) {
    var f = found[i]
    seen[f.path] = true
    var known = byPath[f.path] ? records[byPath[f.path]] : null
    // A "gone" record whose file is back is re-checked, so its category and favorite return.
    if (!known || known.gone || known.size !== f.size || Math.floor(known.mtime) !== Math.floor(f.mtime)) need.push(f)
  }
  // An empty listing means the folder was unreadable or unmounted, not that every shot vanished.
  var gone = []
  if (found.length > 0) {
    for (var k in records) {
      var r = records[k]
      if (!r.trashed && !r.gone && r.path && !seen[r.path]) gone.push(k)
    }
  }
  return { need: need, gone: gone }
}

// Adds or updates records from hashed files. A hash seen before (moved, renamed or
// copied file) keeps its category and favorite and just takes the new path.
function upsert(records, items, app, now) {
  var out = Object.assign({}, records)
  var added = 0
  for (var i = 0; i < items.length; i++) {
    var m = items[i]
    if (!m || !m.hash) continue
    var prev = out[m.hash]
    // Same path, new content (edited in place, for example annotated): the old record is replaced
    // and its category and favorite carry over.
    var carry = null
    if (!prev) {
      for (var oh in out) {
        if (out[oh].path === m.path && oh !== m.hash && !out[oh].trashed) { carry = out[oh]; delete out[oh]; break }
      }
    }
    if (prev) {
      out[m.hash] = Object.assign({}, prev, { path: m.path, size: m.size, mtime: m.mtime, w: m.w, h: m.h, gone: false })
    } else {
      added++
      out[m.hash] = { hash: m.hash, path: m.path, size: m.size, mtime: m.mtime, at: Math.round(m.mtime * 1000), w: m.w, h: m.h, app: m.app || app || appFromName(m.path), cat: carry ? carry.cat : null, fav: carry ? !!carry.fav : false, trashed: false, gone: false, ocr: null, added: now || Date.now() }
    }
  }
  return { records: out, added: added }
}

function markGone(records, hashes) {
  var out = Object.assign({}, records)
  for (var i = 0; i < hashes.length; i++) if (out[hashes[i]]) out[hashes[i]] = Object.assign({}, out[hashes[i]], { gone: true })
  return out
}

// Some tools save "screenshot-<time>-<app>.png"; use that when no focused app was recorded.
function appFromName(path) {
  var m = /^screenshot-\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}-([a-z0-9-]+)\.[a-z]+$/i.exec(baseName(path))
  return m ? m[1].replace(/-[a-z0-9]{12,}$/i, "") : ""
}

// ---- states ----------------------------------------------------------------
function isInbox(r) { return !r.trashed && !r.gone && !r.cat && !r.fav }

function setCat(records, hash, cat) {
  if (!records[hash]) return records
  var out = Object.assign({}, records)
  out[hash] = Object.assign({}, out[hash], { cat: cat || null })
  return out
}

function setFav(records, hash, fav) {
  if (!records[hash]) return records
  var out = Object.assign({}, records)
  out[hash] = Object.assign({}, out[hash], { fav: !!fav })
  return out
}

function setTrashed(records, hash, trashed, now) {
  if (!records[hash]) return records
  var out = Object.assign({}, records)
  out[hash] = Object.assign({}, out[hash], { trashed: !!trashed, trashedAt: trashed ? (now || Date.now()) : null })
  return out
}

function setOcr(records, hash, text) {
  if (!records[hash]) return records
  var out = Object.assign({}, records)
  out[hash] = Object.assign({}, out[hash], { ocr: String(text || "") })
  return out
}

// ---- searching and views ---------------------------------------------------
// Text plus app:, cat:, is:fav|unsorted|trash filters. Plain words match the file name, app,
// category name and the text found inside the image.
function parseQuery(q) {
  var out = { words: [], app: [], cat: [], is: [] }
  var parts = String(q || "").toLowerCase().split(/\s+/)
  for (var i = 0; i < parts.length; i++) {
    var w = parts[i]
    if (!w) continue
    var m = /^(app|cat|is):(.+)$/.exec(w)
    if (!m) out.words.push(w)
    else out[m[1]].push(m[2])
  }
  return out
}

function catName(cats, id) {
  for (var i = 0; i < cats.length; i++) if (cats[i].id === id) return cats[i].name
  return ""
}

// views: inbox, all, fav, trash, old, cat:<id>
function select(records, cats, view, query, oldDays, now) {
  var pq = parseQuery(query)
  var t = now || Date.now()
  var list = []
  for (var h in records) {
    var r = records[h]
    var ok
    if (view === "trash") ok = !!r.trashed
    else if (r.trashed || r.gone) ok = false
    else if (view === "inbox") ok = !r.cat && !r.fav
    else if (view === "fav") ok = !!r.fav
    else if (view === "old") ok = !r.cat && !r.fav && (t - r.at) > (oldDays || 14) * 86400000
    else if (view.indexOf("cat:") === 0) ok = r.cat === view.slice(4)
    else ok = true
    if (!ok) continue
    var name = r.cat ? catName(cats, r.cat).toLowerCase() : ""
    var pass = true
    if (pq.words.length > 0) {
      var hay = (baseName(r.path) + " " + (r.app || "") + " " + name + " " + (r.ocr || "")).toLowerCase()
      for (var i = 0; i < pq.words.length && pass; i++) if (hay.indexOf(pq.words[i]) < 0) pass = false
    }
    for (var a = 0; a < pq.app.length && pass; a++) if ((r.app || "").toLowerCase().indexOf(pq.app[a]) < 0) pass = false
    for (var c = 0; c < pq.cat.length && pass; c++) if (name.indexOf(pq.cat[c]) < 0) pass = false
    for (var s = 0; s < pq.is.length && pass; s++) {
      var v = pq.is[s]
      if (v === "fav") pass = !!r.fav
      else if (v === "unsorted") pass = isInbox(r)
      else if (v === "trash") pass = !!r.trashed
    }
    if (pass) list.push(r)
  }
  list.sort(function(x, y) { return y.at - x.at })
  return list
}

function counts(records, cats, oldDays, now) {
  var c = { inbox: 0, all: 0, fav: 0, trash: 0, old: 0, byCat: {} }
  var t = now || Date.now()
  for (var h in records) {
    var r = records[h]
    if (r.trashed) { c.trash++; continue }
    if (r.gone) continue
    c.all++
    if (r.fav) c.fav++
    if (r.cat) c.byCat[r.cat] = (c.byCat[r.cat] || 0) + 1
    if (!r.cat && !r.fav) {
      c.inbox++
      if ((t - r.at) > (oldDays || 14) * 86400000) c.old++
    }
  }
  return c
}

// Looks up a clipboard image entry (the stock plugin names them <sha256>.<ext>) among known screenshots.
function shotForClipboardImage(records, path) {
  var m = /\/([0-9a-f]{64})\.[a-z]+$/.exec(String(path || ""))
  if (!m) return null
  return records[m[1].slice(0, 32)] || null
}

// file:// URL with every path segment encoded (names may contain #, ? or %).
function fileUrl(path) {
  return "file://" + String(path || "").split("/").map(encodeURIComponent).join("/")
}

if (typeof module !== "undefined") {
  module.exports = {
    defaultCats: defaultCats, emptyStore: emptyStore, parseStore: parseStore, baseName: baseName,
    planScan: planScan, upsert: upsert, markGone: markGone, appFromName: appFromName, isInbox: isInbox,
    setCat: setCat, setFav: setFav, setTrashed: setTrashed, setOcr: setOcr,
    fileUrl: fileUrl, parseQuery: parseQuery, select: select, counts: counts, shotForClipboardImage: shotForClipboardImage
  }
}
