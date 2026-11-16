// Tags: lowercase words, no leading "#", spaces become "-", at most 8 per pin.
function normalizeTags(list) {
  var raw = Array.isArray(list) ? list : (typeof list === "string" ? list.split(/[,\n]+/) : [])
  var out = []
  for (var i = 0; i < raw.length; i++) {
    var t = String(raw[i] || "").toLowerCase().trim().replace(/^#+/, "").replace(/\s+/g, "-").slice(0, 24)
    if (t && out.indexOf(t) < 0) out.push(t)
    if (out.length >= 8) break
  }
  return out
}

function withMeta(entry, value) {
  var g = value && typeof value.group === "string" ? value.group : ""
  var l = value && typeof value.label === "string" ? value.label.trim() : ""
  if (g) entry.group = g
  if (l) entry.label = l
  if (value && value.fav === true) entry.fav = true
  var tg = normalizeTags(value && value.tags)
  if (tg.length) entry.tags = tg
  if (value && typeof value.at === "number" && isFinite(value.at)) entry.at = value.at
  return entry
}

function normalizeEntry(value) {
  if (typeof value === "string")
    return value.trim().length > 0 ? { type: "text", text: value } : null

  if (!value || typeof value !== "object") return null

  var type = String(value.type || value.kind || "")
  if (type === "text") {
    var text = String(value.text || "")
    return text.trim().length > 0 ? withMeta({ type: "text", text: text }, value) : null
  }

  if (type === "image") {
    var path = String(value.path || "")
    if (!path) return null
    var entry = {
      type: "image",
      path: path,
      mime: String(value.mime || "image/png")
    }
    if (value.capturedAt !== undefined && value.capturedAt !== null)
      entry.capturedAt = String(value.capturedAt)
    return withMeta(entry, value)
  }

  return null
}

function entryKey(entry) {
  if (!entry) return ""
  if (entry.type === "image") return "image:" + String(entry.path || "")
  return "text:" + String(entry.text || "")
}

function parseHistory(raw) {
  try {
    var parsed = JSON.parse(String(raw || "[]"))
    var next = []
    if (!Array.isArray(parsed)) return next

    for (var i = 0; i < parsed.length; i++) {
      var entry = normalizeEntry(parsed[i])
      if (entry) next.push(entry)
    }
    return next
  } catch (e) {
    return []
  }
}

// Like parseHistory, but reports a missing, empty or corrupt file separately
// from a genuinely empty list, so callers never overwrite data they failed to read.
function parseHistoryStrict(raw) {
  var text = String(raw == null ? "" : raw).trim()
  if (!text) return { ok: false, list: [] }
  try {
    var parsed = JSON.parse(text)
    if (!Array.isArray(parsed)) return { ok: false, list: [] }
    var list = []
    for (var i = 0; i < parsed.length; i++) {
      var entry = normalizeEntry(parsed[i])
      if (entry) list.push(entry)
    }
    return { ok: true, list: list }
  } catch (e) {
    return { ok: false, list: [] }
  }
}

function addEntry(history, entry, limit) {
  var normalized = normalizeEntry(entry)
  var max = limit === undefined || limit === null ? 100 : Number(limit)
  if (isNaN(max)) max = 100
  max = Math.max(0, max)
  if (!normalized) return Array.isArray(history) ? history.slice(0, max) : []
  if (max === 0) return []

  var key = entryKey(normalized)
  var next = [normalized]
  var values = Array.isArray(history) ? history : []

  for (var i = 0; i < values.length && next.length < max; i++) {
    var existing = normalizeEntry(values[i])
    if (!existing || entryKey(existing) === key) continue
    next.push(existing)
  }

  return next
}

function removeEntryAt(history, index) {
  var values = Array.isArray(history) ? history : []
  var target = Number(index)
  if (isNaN(target) || target < 0 || target >= values.length) return values.slice()

  var next = values.slice()
  next.splice(target, 1)
  return next
}

function clearHistory() {
  return []
}

function parseEntryJson(line) {
  var raw = String(line || "").trim()
  if (!raw) return null
  try { return normalizeEntry(JSON.parse(raw)) } catch (e) { return null }
}

function searchableText(entry) {
  if (!entry) return ""
  if (entry.type === "image") return "image screenshot " + String(entry.mime || "") + " " + String(entry.capturedAt || "")
  return String(entry.label || "") + " " + (entry.tags ? "#" + entry.tags.join(" #") + " " : "") + String(entry.text || "") + " " + fileEntryText(entry)
}

function decodeFileUri(uri) {
  var value = String(uri || "").trim()
  if (value.indexOf("file://") !== 0) return ""

  var path = value.substring(7)
  if (path.indexOf("localhost/") === 0) path = path.substring(9)
  if (path.charAt(0) !== "/") return ""

  try { return decodeURIComponent(path) } catch (e) { return path }
}

function filePaths(entry) {
  if (!entry || entry.type !== "text") return []

  var lines = String(entry.text || "").split(/\r?\n/)
  var paths = []
  for (var i = 0; i < lines.length; i++) {
    var path = decodeFileUri(lines[i])
    if (path) paths.push(path)
  }
  return paths
}

function fileName(path) {
  var parts = String(path || "").split("/")
  return parts.length > 0 ? parts[parts.length - 1] : String(path || "")
}

function isImagePath(path) {
  return /\.(png|jpe?g|webp|gif|bmp|tiff?)$/i.test(String(path || ""))
}

function fileEntryText(entry) {
  var paths = filePaths(entry)
  if (paths.length === 0) return ""
  if (paths.length === 1) return fileName(paths[0])
  return paths.length + " files"
}

function imagePreviewText(entry) {
  var timestamp = String(entry && entry.capturedAt || "")
  if (!timestamp) return "Image"

  var label = String(entry && entry.mime || "") === "image/png" ? "Screenshot" : "Image"
  return label + " from " + timestamp
}

function previewText(entry) {
  if (!entry) return ""
  if (entry.type === "image") return imagePreviewText(entry)
  var fileText = fileEntryText(entry)
  if (fileText) return fileText
  return String(entry.text || "").replace(/\s+/g, " ")
}

function fullText(entry) {
  if (!entry) return ""
  var paths = filePaths(entry)
  if (paths.length > 0) return paths.join("\n")
  return String(entry.text || "")
}

// The picker only ever searches and renders a prefix of an entry, so scan and
// render just that much. A single huge paste otherwise costs hundreds of
// megabytes of string work on every keystroke and stalls the whole shell.
// Pasting reads the full entry back from history by index, so nothing is lost.
var displayTextLimit = 8192

function cappedEntry(entry) {
  if (!entry || entry.type !== "text" || entry.text.length <= displayTextLimit) return entry

  // Cut on a line break so a file:// URI never truncates into a bogus path.
  var cut = entry.text.lastIndexOf("\n", displayTextLimit)
  var capped = { type: "text", text: entry.text.slice(0, cut > 0 ? cut : displayTextLimit) }
  if (entry.group) capped.group = entry.group
  if (entry.label) capped.label = entry.label
  if (entry.fav) capped.fav = true
  if (entry.tags) capped.tags = entry.tags
  if (entry.at) capped.at = entry.at
  return capped
}

// Lowercase only: {{date}} expands, but {{DATE}} or {{.Names}} (other tools' tokens) stay literal.
var templateRe = /\{\{\s*([a-z]+)(?::([^}]*))?\s*\}\}/g

function luhnOk(digits) {
  var sum = 0
  var alt = false
  for (var i = digits.length - 1; i >= 0; i--) {
    var d = digits.charCodeAt(i) - 48
    if (alt) { d *= 2; if (d > 9) d -= 9 }
    sum += d
    alt = !alt
  }
  return sum % 10 === 0
}

function entropy(s) {
  var counts = {}
  for (var i = 0; i < s.length; i++) counts[s.charAt(i)] = (counts[s.charAt(i)] || 0) + 1
  var h = 0
  for (var c in counts) { var p = counts[c] / s.length; h -= p * Math.log(p) / Math.LN2 }
  return h
}

// ---- key hashing ------------------------------------------------------------
// State files are keyed by a hash of the entry, never by its text, so a copied
// secret is not stored a second time in plain text.
var sha256K = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
]

function sha256hex(message) {
  var bytes = []
  var utf8 = unescape(encodeURIComponent(String(message)))
  for (var i = 0; i < utf8.length; i++) bytes.push(utf8.charCodeAt(i))
  var bitLen = bytes.length * 8
  bytes.push(0x80)
  while (bytes.length % 64 !== 56) bytes.push(0)
  var hi = Math.floor(bitLen / 4294967296)
  var lo = bitLen >>> 0
  for (var b = 3; b >= 0; b--) bytes.push((hi >>> (b * 8)) & 0xff)
  for (var c = 3; c >= 0; c--) bytes.push((lo >>> (c * 8)) & 0xff)

  var h = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
  var w = new Array(64)
  function rotr(x, n) { return (x >>> n) | (x << (32 - n)) }
  for (var off = 0; off < bytes.length; off += 64) {
    for (var t = 0; t < 16; t++) w[t] = ((bytes[off + t * 4] << 24) | (bytes[off + t * 4 + 1] << 16) | (bytes[off + t * 4 + 2] << 8) | bytes[off + t * 4 + 3]) >>> 0
    for (var u = 16; u < 64; u++) {
      var s0 = rotr(w[u - 15], 7) ^ rotr(w[u - 15], 18) ^ (w[u - 15] >>> 3)
      var s1 = rotr(w[u - 2], 17) ^ rotr(w[u - 2], 19) ^ (w[u - 2] >>> 10)
      w[u] = (w[u - 16] + s0 + w[u - 7] + s1) >>> 0
    }
    var a = h[0], bb = h[1], cc = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
    for (var r = 0; r < 64; r++) {
      var S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
      var ch = (e & f) ^ (~e & g)
      var t1 = (hh + S1 + ch + sha256K[r] + w[r]) >>> 0
      var S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
      var maj = (a & bb) ^ (a & cc) ^ (bb & cc)
      var t2 = (S0 + maj) >>> 0
      hh = g; g = f; f = e; e = (d + t1) >>> 0; d = cc; cc = bb; bb = a; a = (t1 + t2) >>> 0
    }
    h[0] = (h[0] + a) >>> 0; h[1] = (h[1] + bb) >>> 0; h[2] = (h[2] + cc) >>> 0; h[3] = (h[3] + d) >>> 0
    h[4] = (h[4] + e) >>> 0; h[5] = (h[5] + f) >>> 0; h[6] = (h[6] + g) >>> 0; h[7] = (h[7] + hh) >>> 0
  }
  var out = ""
  for (var k = 0; k < 8; k++) out += ("00000000" + h[k].toString(16)).slice(-8)
  return out
}

var hashCache = {}
var hashCacheSize = 0
function keyHash(key) {
  var k = String(key)
  var hit = hashCache[k]
  if (hit) return hit
  var h = sha256hex(k).slice(0, 32)
  if (hashCacheSize > 5000) { hashCache = {}; hashCacheSize = 0 }
  hashCache[k] = h
  hashCacheSize++
  return h
}

// Turns old plain-text keys ("text:...", "image:...") into hashed ones.
function migrateKeys(obj) {
  var out = {}
  for (var k in (obj || {})) out[/^(text|image):/.test(k) ? keyHash(k) : k] = obj[k]
  return out
}

// Returns a short label when the text looks like a credential, else "".
// Only the first 4 KB is scanned, so a long pasted .env is still caught.
function secretKind(text) {
  var t = String(text || "").slice(0, 4096).trim()
  if (!t) return ""
  if (/-----BEGIN [A-Z ]*PRIVATE KEY( BLOCK)?-----/.test(t)) return "Private key"
  if (/\bsk-(ant-)?[A-Za-z0-9_-]{20,}/.test(t) || /\b[sr]k_(live|test)_[A-Za-z0-9]{16,}/.test(t)) return "API key"
  if (/\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}/.test(t) || /github_pat_[A-Za-z0-9_]{40,}/.test(t)) return "GitHub token"
  if (/\bglpat-[A-Za-z0-9_-]{16,}/.test(t) || /\bhf_[A-Za-z0-9]{30,}/.test(t) || /\bnpm_[A-Za-z0-9]{30,}/.test(t)) return "Access token"
  if (/\bAKIA[0-9A-Z]{16}\b/.test(t)) return "AWS key"
  if (/\bxox[baprs]-[A-Za-z0-9-]{10,}/.test(t)) return "Slack token"
  if (/\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/.test(t)) return "JWT"
  if (/\bBearer\s+[A-Za-z0-9._~+\/-]{20,}/.test(t)) return "Bearer token"
  if (/\b[a-z][a-z0-9+.-]*:\/\/[^\s:@\/]+:[^\s@\/]{3,}@[^\s\/]+/i.test(t)) return "Database URL"
  if (/^[\d -]{13,23}$/.test(t)) {
    var digits = t.replace(/[ -]/g, "")
    if (digits.length >= 13 && digits.length <= 19 && luhnOk(digits)) return "Card number"
  }
  if (/(password|passwd|secret|token|api[_-]?key)["']?\s*[:=]\s*["']?[^\s"'(){}]{6,}(?=[\s"',;}]|$)/i.test(t)) return "Credential"
  if (/^[A-Za-z0-9+_=-]{32,}$/.test(t) && !/^[0-9a-f]+$/i.test(t) && !/^[a-z0-9]+(-[a-z0-9]+){2,}$/i.test(t)
      && /\d/.test(t) && /[A-Za-z]/.test(t) && entropy(t) >= 3.6) return "Token"
  return ""
}

// Auto-delete only acts on these; the guess-based kinds ("Credential", "Token") are masked but kept.
var sureSecretKinds = ["Private key", "API key", "GitHub token", "Access token", "AWS key", "Slack token", "JWT", "Bearer token", "Database URL", "Card number"]

function secretIsSure(kind) { return sureSecretKinds.indexOf(kind) >= 0 }

function templateTokens(text) {
  var asks = []
  var re = new RegExp(templateRe.source, "g")
  var m
  var any = false
  while ((m = re.exec(String(text || ""))) !== null) {
    any = true
    if (m[1] === "ask") {
      var name = String(m[2] || "Value").trim() || "Value"
      if (asks.indexOf(name) < 0) asks.push(name)
    }
  }
  return { any: any, asks: asks }
}

function pad2(n) { return (n < 10 ? "0" : "") + n }

function expandTemplate(text, ctx) {
  var now = ctx && ctx.now ? ctx.now : new Date()
  var days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
  var date = now.getFullYear() + "-" + pad2(now.getMonth() + 1) + "-" + pad2(now.getDate())
  var time = pad2(now.getHours()) + ":" + pad2(now.getMinutes())
  var re = new RegExp(templateRe.source, "g")
  return String(text || "").replace(re, function(whole, kind, arg) {
    switch (kind) {
    case "date": return date
    case "time": return time
    case "datetime": return date + " " + time
    case "weekday": return days[now.getDay()]
    case "clip": return String(ctx && ctx.clip || "")
    case "uuid": return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function(c) { var r = Math.floor(Math.random() * 16); return (c === "x" ? r : (r & 3) | 8).toString(16) })
    case "ask": return String((ctx && ctx.asks && ctx.asks[String(arg || "Value").trim() || "Value"]) || "")
    }
    return whole
  })
}

var transformList = [
  { id: "plain", label: "Plain text (trim lines)" },
  { id: "oneline", label: "Single line" },
  { id: "upper", label: "UPPERCASE" },
  { id: "lower", label: "lowercase" },
  { id: "json", label: "JSON pretty" },
  { id: "jsonmin", label: "JSON minify" },
  { id: "b64enc", label: "Base64 encode" },
  { id: "b64dec", label: "Base64 decode" },
  { id: "urlenc", label: "URL encode" },
  { id: "urldec", label: "URL decode" }
]

// Returns the transformed string, or null when the input cannot be transformed.
function applyTransform(id, text, codec) {
  var t = String(text || "")
  try {
    switch (id) {
    case "plain": return t.replace(/\r/g, "").split("\n").map(function(l) { return l.replace(/\s+$/, "") }).join("\n").trim()
    case "oneline": return t.replace(/\s+/g, " ").trim()
    case "upper": return t.toUpperCase()
    case "lower": return t.toLowerCase()
    case "json": return JSON.stringify(JSON.parse(t), null, 2)
    case "jsonmin": return JSON.stringify(JSON.parse(t))
    case "b64enc": return codec.btoa(unescape(encodeURIComponent(t)))
    case "b64dec": return decodeURIComponent(escape(codec.atob(t.trim())))
    case "urlenc": return encodeURIComponent(t)
    case "urldec": return decodeURIComponent(t)
    }
  } catch (e) { return null }
  return null
}

function ago(ms, now) {
  var d = Math.max(0, Math.floor(((now || Date.now()) - ms) / 1000))
  if (d < 10) return "now"
  if (d < 60) return d + "s"
  if (d < 3600) return Math.floor(d / 60) + "m"
  if (d < 86400) return Math.floor(d / 3600) + "h"
  return Math.floor(d / 86400) + "d"
}

function swatchOf(entry) {
  if (!entry || entry.type !== "text") return ""
  var t = String(entry.text || "").trim()
  return /^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(t) ? t : ""
}

function kindOf(entry, isFile) {
  if (!entry) return "text"
  if (entry.type === "image") return "image"
  if (isFile) return "file"
  var t = String(entry.text || "").trim()
  if (/^https?:\/\/\S+$/i.test(t)) return "url"
  if (swatchOf(entry)) return "color"
  if (templateRe.test(t)) { templateRe.lastIndex = 0; return "template" }
  templateRe.lastIndex = 0
  if (/^(sudo |git |docker |ssh |npm |pnpm |cd |ls |cat |curl |journalctl |systemctl |select |insert |update )/i.test(t) || /(=>|\{\s*$|;\s*$|\$\(|\s--[a-z])/.test(t)) return "code"
  return "text"
}

function displayRows(history, query, limit, meta) {
  var values = Array.isArray(history) ? history : []
  var needle = String(query || "").trim().toLowerCase()
  var max = limit === undefined || limit === null ? 50 : Number(limit)
  if (isNaN(max)) max = 50
  max = Math.max(0, max)
  if (max === 0) return []

  var rows = []
  var needleWantsSecret = needle.length > 0 && "secret".indexOf(needle) >= 0

  for (var i = 0; i < values.length; i++) {
    var full = normalizeEntry(values[i])
    var entry = cappedEntry(full)
    if (!entry) continue
    var key = entryKey(full)
    var m = meta && meta[keyHash(key)] ? meta[keyHash(key)] : null
    var secret = ""
    if (needle) {
      // The secret check is the expensive part; only run it early when the query could match "secret".
      if (needleWantsSecret && full.type === "text") secret = secretKind(full.text)
      if ((searchableText(entry) + " " + (m && m.app ? m.app : "") + (secret ? " secret" : "")).toLowerCase().indexOf(needle) < 0) continue
    }
    if (!secret && full.type === "text") secret = secretKind(full.text)

    var paths = filePaths(entry)
    var isFile = paths.length > 0
    var isImage = entry.type === "image"
    var previewPath = isImage ? String(entry.path || "") : (isFile && paths.length === 1 && isImagePath(paths[0]) ? paths[0] : "")
    rows.push({
      entryType: isFile ? "file" : entry.type,
      fullText: isImage ? "" : fullText(entry),
      previewText: entry.label ? entry.label : previewText(entry),
      previewImage: previewPath,
      path: isImage ? String(entry.path || "") : (isFile && paths.length === 1 ? paths[0] : ""),
      mime: isImage ? String(entry.mime || "image/png") : "text/plain",
      label: entry.label || "",
      group: entry.group || "",
      fav: !!entry.fav,
      tagsText: entry.tags ? entry.tags.join(" ") : "",
      key: key,
      app: m && m.app ? m.app : "",
      ts: m && m.t ? m.t : 0,
      seen: !!(m && m.seen),
      uses: m && m.n ? m.n : 0,
      secret: secret,
      kind: kindOf(entry, isFile),
      swatch: swatchOf(entry),
      subtitle: entry.label ? previewText(entry) : "",
      index: i
    })
    if (rows.length >= max) break
  }

  return rows
}

// Pins live in their own file as full entry copies, so they survive the
// history limit and "clear history". The picker shows them first, then the
// recent history minus anything already pinned. History entries keep their
// original file index (masked, not filtered) because paste/open address the
// stock history file by index.
function addPin(pins, entry, group) {
  var normalized = normalizeEntry(entry)
  var values = Array.isArray(pins) ? pins : []
  if (!normalized) return values.slice()

  var key = entryKey(normalized)
  var carried = ""
  var label = normalized.label
  for (var j = 0; j < values.length; j++) {
    var old = normalizeEntry(values[j])
    if (old && entryKey(old) === key) { carried = old.group || ""; label = old.label || label }
  }
  if (group) normalized.group = group
  else if (carried) normalized.group = carried
  if (label) normalized.label = label
  normalized.at = Date.now()

  var next = [normalized]
  for (var i = 0; i < values.length; i++) {
    var existing = normalizeEntry(values[i])
    if (existing && entryKey(existing) !== key) next.push(existing)
  }
  return next
}

function setPinFav(pins, index, fav) {
  return mapPin(pins, index, function(e) { if (fav) e.fav = true; else delete e.fav })
}

function setPinTags(pins, index, tags) {
  var t = normalizeTags(tags)
  return mapPin(pins, index, function(e) { if (t.length) e.tags = t; else delete e.tags })
}

// Counts for the strip: how many pins are favorites and how many carry each tag (most used first).
function tagCounts(pins) {
  var favs = 0
  var map = {}
  var values = Array.isArray(pins) ? pins : []
  for (var i = 0; i < values.length; i++) {
    var e = normalizeEntry(values[i])
    if (!e) continue
    if (e.fav) favs++
    var tg = e.tags || []
    for (var j = 0; j < tg.length; j++) map[tg[j]] = (map[tg[j]] || 0) + 1
  }
  var tags = Object.keys(map).map(function(t) { return { tag: t, count: map[t] } })
  tags.sort(function(a, b) { return b.count - a.count || (a.tag < b.tag ? -1 : 1) })
  return { favs: favs, tags: tags, total: values.length }
}

function mapPin(pins, index, fn) {
  var values = Array.isArray(pins) ? pins : []
  var next = []
  for (var i = 0; i < values.length; i++) {
    var e = normalizeEntry(values[i])
    if (!e) continue
    if (i === Number(index)) { fn(e); e.at = Date.now() }
    next.push(e)
  }
  return next
}

function setPinGroup(pins, index, group) {
  return mapPin(pins, index, function(e) { if (group) e.group = group; else delete e.group })
}

function setPinLabel(pins, index, label) {
  var l = String(label || "").trim()
  return mapPin(pins, index, function(e) { if (l) e.label = l; else delete e.label })
}

function ungroupPins(pins, group) {
  var values = Array.isArray(pins) ? pins : []
  var next = []
  for (var i = 0; i < values.length; i++) {
    var e = normalizeEntry(values[i])
    if (!e) continue
    if (e.group === group) { delete e.group; e.at = Date.now() }
    next.push(e)
  }
  return next
}

function pinIndexByKey(pins, key) {
  var values = Array.isArray(pins) ? pins : []
  for (var i = 0; i < values.length; i++) {
    var e = normalizeEntry(values[i])
    if (e && entryKey(e) === key) return i
  }
  return -1
}

function pinnedKeys(pins) {
  var out = {}
  var values = Array.isArray(pins) ? pins : []
  for (var i = 0; i < values.length; i++) {
    var e = normalizeEntry(values[i])
    if (e) out[entryKey(e)] = true
  }
  return out
}

// Search syntax: free text plus is:<kind>, app:<name>, in:<group>.
function parseQuery(query) {
  var out = { text: "", is: [], app: [], inGroup: [], tag: [] }
  var words = String(query || "").split(/\s+/)
  var rest = []
  for (var i = 0; i < words.length; i++) {
    var w = words[i]
    var m = /^(is|app|in|tag):(.+)$/i.exec(w)
    if (!m) { if (w) rest.push(w); continue }
    var v = m[2].toLowerCase()
    var k = m[1].toLowerCase()
    if (k === "is") out.is.push(v)
    else if (k === "app") out.app.push(v)
    else if (k === "tag") out.tag.push(v.replace(/^#/, ""))
    else out.inGroup.push(v)
  }
  out.text = rest.join(" ")
  out.filtered = out.is.length + out.app.length + out.inGroup.length + out.tag.length > 0
  return out
}

function rowMatchesFilters(row, pq, groupNames) {
  var i
  for (i = 0; i < pq.is.length; i++) {
    var v = pq.is[i]
    var ok = v === "fav" ? !!row.fav : v === "pinned" ? row.pinned : v === "unpinned" ? !row.pinned : v === "secret" ? row.secret !== "" : row.kind === v || (v === "text" && row.kind === "text")
    if (!ok) return false
  }
  for (i = 0; i < pq.app.length; i++) if ((row.app || "").indexOf(pq.app[i]) < 0) return false
  for (i = 0; i < pq.tag.length; i++) if ((" " + (row.tagsText || "") + " ").indexOf(pq.tag[i]) < 0) return false
  for (i = 0; i < pq.inGroup.length; i++) {
    var name = row.pinned && row.group ? String((groupNames && groupNames[row.group]) || "").toLowerCase() : ""
    if (!name || name.indexOf(pq.inGroup[i]) < 0) return false
  }
  return true
}

// Rows for one view: "recent" (unpinned history), "all" (every pin), "frequent"
// (most pasted) or a group id. A non-empty query with scopeAll, or an in:
// filter, searches every row. History rows keep their stock-file index
// (masked, never filtered) because paste/open address that file by index; pin
// rows carry pinIndex into the pins file.
// The strip inside "All pinned": "all", "fav", or "tag:<name>".
function subMatch(row, sub) {
  if (!sub || sub === "all") return true
  if (sub === "fav") return !!row.fav
  if (sub.indexOf("tag:") === 0) return (" " + (row.tagsText || "") + " ").indexOf(" " + sub.slice(4) + " ") >= 0
  return true
}

// Search runs on every keystroke, so the per-entry work (normalize, hash the
// key for meta, build the lowercased haystack) happens once per data change in
// buildIndex. queryIndex then only scans strings, and builds full rows (secret
// check, kind, swatch) for the entries it actually returns.
// Pins come first, then history minus anything pinned; history items keep their
// original file index because paste/open address the stock file by index.
function buildIndex(history, pins, meta) {
  var items = []
  var pinValues = Array.isArray(pins) ? pins : []
  var historyValues = Array.isArray(history) ? history : []
  var pinned = {}
  function add(raw, i, isPin) {
    var full = normalizeEntry(raw)
    if (!full) return
    var key = entryKey(full)
    if (isPin) pinned[key] = true
    else if (pinned[key]) return
    var entry = cappedEntry(full)
    var m = meta ? meta[keyHash(key)] || null : null
    var head = entry.label ? String(entry.label) : previewText(entry).slice(0, 200)
    items.push({
      full: full, entry: entry, key: key, m: m, pinned: isPin, i: i, order: items.length,
      group: isPin ? entry.group || "" : "",
      uses: m && m.n ? m.n : 0,
      head: head.toLowerCase(),
      hay: (searchableText(entry) + " " + (m && m.app ? m.app : "")).toLowerCase(),
      secret: null, row: null
    })
  }
  for (var p = 0; p < pinValues.length; p++) add(pinValues[p], p, true)
  for (var h = 0; h < historyValues.length; h++) add(historyValues[h], h, false)
  return { items: items }
}

function itemSecret(it) {
  if (it.secret === null) it.secret = it.full.type === "text" ? secretKind(it.full.text) : ""
  return it.secret
}

function itemRow(it) {
  if (it.row) return it.row
  var entry = it.entry
  var m = it.m
  var paths = filePaths(entry)
  var isFile = paths.length > 0
  var isImage = entry.type === "image"
  it.row = {
    entryType: isFile ? "file" : entry.type,
    fullText: isImage ? "" : fullText(entry),
    previewText: entry.label ? entry.label : previewText(entry),
    previewImage: isImage ? String(entry.path || "") : (isFile && paths.length === 1 && isImagePath(paths[0]) ? paths[0] : ""),
    path: isImage ? String(entry.path || "") : (isFile && paths.length === 1 ? paths[0] : ""),
    mime: isImage ? String(entry.mime || "image/png") : "text/plain",
    label: entry.label || "",
    group: it.group,
    fav: !!entry.fav,
    tagsText: entry.tags ? entry.tags.join(" ") : "",
    key: it.key,
    app: m && m.app ? m.app : "",
    ts: m && m.t ? m.t : 0,
    seen: !!(m && m.seen),
    uses: it.uses,
    secret: itemSecret(it),
    kind: kindOf(entry, isFile),
    swatch: swatchOf(entry),
    subtitle: entry.label ? previewText(entry) : "",
    pinned: it.pinned,
    pinIndex: it.pinned ? it.i : -1,
    index: it.pinned ? -1 : it.i
  }
  return it.row
}

function isWordChar(c) { return /[a-z0-9]/.test(c) }

// How well one lowercased word hits an item: 0 no match, 1 inside a word,
// 2 at a word start, 3 at the start of the title. The literal word "secret"
// (or a prefix of it) also matches entries that look like secrets.
function wordScore(it, w) {
  var at = it.hay.indexOf(w)
  if (at < 0) return "secret".indexOf(w) === 0 && itemSecret(it) ? 1 : 0
  if (it.head.indexOf(w) === 0) return 3
  while (at >= 0) {
    if (at === 0 || !isWordChar(it.hay.charAt(at - 1))) return 2
    at = it.hay.indexOf(w, at + 1)
  }
  return 1
}

// Letters of w appear in order in s (for typos like "gtihub" no; "ghub" yes).
function subsequence(s, w) {
  var j = 0
  for (var i = 0; i < s.length && j < w.length; i++) if (s.charAt(i) === w.charAt(j)) j++
  return j === w.length
}

function queryIndex(index, query, limit, view, scopeAll, groupNames, sub) {
  var max = limit === undefined || limit === null ? 50 : Number(limit)
  if (isNaN(max)) max = 50
  max = Math.max(0, max)
  var items = index && index.items ? index.items : []
  var pq = parseQuery(query)
  var phrase = pq.text.toLowerCase()
  var words = phrase ? phrase.split(/\s+/) : []
  var searching = words.length > 0 || pq.filtered
  var wide = (words.length > 0 && !!scopeAll) || pq.inGroup.length > 0

  function inScope(it) {
    if (wide) return true
    if (view === "recent") return !it.pinned
    if (view === "all") return it.pinned && subMatch(itemRow(it), sub)
    if (view === "frequent") return it.uses > 0
    return it.pinned && it.group === view
  }

  function run(fuzzy) {
    var hits = []
    var other = 0
    for (var i = 0; i < items.length; i++) {
      var it = items[i]
      var score = 0
      if (words.length) {
        for (var k = 0; k < words.length; k++) {
          var s = fuzzy ? (subsequence(it.head, words[k]) ? 1 : 0) : wordScore(it, words[k])
          if (!s) { score = -1; break }
          score += s
        }
        if (score < 0) continue
        if (!fuzzy && words.length > 1 && it.hay.indexOf(phrase) >= 0) score += 2
        if (it.entry.fav) score += 0.5
      }
      if (pq.filtered && !rowMatchesFilters(itemRow(it), pq, groupNames)) continue
      if (!inScope(it)) { other++; continue }
      hits.push({ it: it, score: score })
      // Unsorted results can stop early once the page is full.
      if (!words.length && view !== "frequent" && hits.length >= max && !searching) break
    }
    return { hits: hits, other: other }
  }

  var res = run(false)
  if (words.length && res.hits.length === 0 && res.other === 0 && phrase.length >= 3) res = run(true)
  var freq = view === "frequent" && !wide
  if (words.length || freq) {
    res.hits.sort(function(a, b) {
      return (b.score - a.score) || (freq ? b.it.uses - a.it.uses : 0) || (a.it.order - b.it.order)
    })
  }
  var rows = []
  for (var r = 0; r < res.hits.length && rows.length < max; r++) rows.push(itemRow(res.hits[r].it))
  return { rows: rows, elsewhere: searching && !wide ? res.other : 0 }
}

// Title markup with the searched words in bold accent colour, for a StyledText
// label. Returns "" when nothing matches so the caller keeps plain text.
function highlightTitle(text, query, color) {
  var words = parseQuery(query).text.toLowerCase().split(/\s+/).filter(function(w) { return w })
  if (!words.length) return ""
  var t = String(text || "").replace(/\s+/g, " ").slice(0, 300)
  var low = t.toLowerCase()
  var marks = []
  for (var k = 0; k < words.length; k++) {
    var at = low.indexOf(words[k])
    while (at >= 0) { marks.push([at, at + words[k].length]); at = low.indexOf(words[k], at + words[k].length) }
  }
  if (!marks.length) return ""
  marks.sort(function(a, b) { return a[0] - b[0] })
  function esc(x) { return x.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
  var out = ""
  var pos = 0
  for (var i = 0; i < marks.length; i++) {
    var a = Math.max(marks[i][0], pos)
    var b = marks[i][1]
    if (b <= a) continue
    out += esc(t.slice(pos, a)) + "<font color=\"" + color + "\"><b>" + esc(t.slice(a, b)) + "</b></font>"
    pos = b
  }
  return out + esc(t.slice(pos))
}

function combinedRows(history, pins, query, limit, view, scopeAll, meta, groupNames, sub) {
  return queryIndex(buildIndex(history, pins, meta), query, limit, view, scopeAll, groupNames, sub)
}

// The overlay's long-term list: everything the stock plugin currently holds
// (newest first), then older entries kept from before the stock plugin dropped them.
function mergeArchive(stock, archive, cap) {
  var out = []
  var seen = {}
  function add(list) {
    var values = Array.isArray(list) ? list : []
    for (var i = 0; i < values.length; i++) {
      var n = normalizeEntry(values[i])
      if (!n) continue
      var k = entryKey(n)
      if (seen[k]) continue
      seen[k] = true
      out.push(n)
    }
  }
  add(stock)
  add(archive)
  var c = Number(cap) || 0
  return c > 0 && out.length > c ? out.slice(0, c) : out
}

function counts(history, pins, meta) {
  var pinned = pinnedKeys(pins)
  var values = Array.isArray(history) ? history : []
  var recent = 0
  for (var i = 0; i < values.length; i++) {
    var n = normalizeEntry(values[i])
    if (n && !pinned[entryKey(n)]) recent++
  }
  var byGroup = {}
  var total = 0
  var pv = Array.isArray(pins) ? pins : []
  for (var j = 0; j < pv.length; j++) {
    var e = normalizeEntry(pv[j])
    if (!e) continue
    total++
    if (e.group) byGroup[e.group] = (byGroup[e.group] || 0) + 1
  }
  var frequent = 0
  if (meta) {
    var live = {}
    for (var f = 0; f < values.length; f++) { var fe = normalizeEntry(values[f]); if (fe) live[entryKey(fe)] = true }
    for (var g = 0; g < pv.length; g++) { var pe = normalizeEntry(pv[g]); if (pe) live[entryKey(pe)] = true }
    for (var k in live) { var mh = keyHash(k); if (meta[mh] && meta[mh].n > 0) frequent++ }
  }
  return { recent: recent, all: total, frequent: frequent, byGroup: byGroup }
}

// ---- backup, import and folder sync ---------------------------------------
var tombstoneDays = 90

function tombstoneFor(tombs, key, at) {
  var next = Object.assign({}, tombs || {})
  next[/^(text|image):/.test(String(key)) ? keyHash(key) : key] = at
  return next
}

function pruneTombstones(tombs, now) {
  var out = {}
  for (var k in (tombs || {})) if (now - tombs[k] < tombstoneDays * 86400000) out[k] = tombs[k]
  return out
}

// Merges two {pins, groups, tombstones} states. The newer change wins per
// entry; a tombstone newer than an entry's last change removes it, so an
// unpin on one machine reaches the other. Image pins are local-only paths, so
// images in the remote side are ignored.
function mergeSnapshots(local, remote, now) {
  var t = now || Date.now()
  // A remote timestamp far in the future would win every later comparison forever (and a
  // future tombstone would keep deleting a pin you re-add), so timestamps are capped at a day ahead.
  var future = t + 86400000
  function clampAt(v) { return typeof v === "number" && isFinite(v) ? Math.min(v, future) : 0 }
  function cleanTombs(obj) {
    var out = {}
    for (var k in (obj || {})) { var v = clampAt(obj[k]); if (v > 0) out[k] = v }
    return out
  }
  var tombs = cleanTombs(migrateKeys(remote && remote.tombstones))
  var lt = cleanTombs(migrateKeys(local && local.tombstones))
  for (var tk in lt) tombs[tk] = Math.max(tombs[tk] || 0, lt[tk])

  var byKey = {}
  var order = []
  // The newer change wins; on an exact tie both machines pick the same side
  // (the larger JSON), so they converge instead of rewriting each other.
  function newer(a, b) {
    var aa = a.at || 0, ba = b.at || 0
    if (aa !== ba) return aa > ba
    return JSON.stringify(a) > JSON.stringify(b)
  }
  function take(list, isRemote) {
    var values = Array.isArray(list) ? list : []
    for (var i = 0; i < values.length; i++) {
      var n = normalizeEntry(values[i])
      if (!n || (isRemote && n.type === "image")) continue
      if (n.at !== undefined) n.at = clampAt(n.at)
      var key = entryKey(n)
      if (!byKey[key]) { byKey[key] = n; order.push(key) }
      else if (newer(n, byKey[key])) byKey[key] = n
    }
  }
  take(local && local.pins, false)
  take(remote && remote.pins, true)

  var pins = []
  for (var o = 0; o < order.length; o++) {
    var e = byKey[order[o]]
    var th = tombs[keyHash(order[o])]
    if (th && th >= (e.at || 0)) continue
    pins.push(e)
  }

  // Groups carry their own timestamp; a "group:<id>" tombstone removes one. Only the four known
  // fields are kept, so a hostile file cannot smuggle in objects the UI would choke on.
  function cleanGroup(x) {
    if (!x || typeof x !== "object" || typeof x.id !== "string" || !x.id || typeof x.name !== "string") return null
    var out = { id: x.id.slice(0, 80), name: x.name.slice(0, 64), h: typeof x.h === "number" && isFinite(x.h) ? x.h : 0 }
    if (x.at !== undefined) out.at = clampAt(x.at)
    return out
  }
  var gById = {}
  var gOrder = []
  var gl = ((local && local.groups) || []).concat((remote && remote.groups) || [])
  for (var g = 0; g < gl.length; g++) {
    var grp = cleanGroup(gl[g])
    if (!grp) continue
    if (!gById[grp.id]) { gById[grp.id] = grp; gOrder.push(grp.id) }
    else if (newer(grp, gById[grp.id])) gById[grp.id] = grp
  }
  var groups = []
  for (var gi = 0; gi < gOrder.length; gi++) {
    var gg = gById[gOrder[gi]]
    var gt = tombs["group:" + gg.id]
    if (gt && gt >= (gg.at || 0)) continue
    groups.push(gg)
  }
  return { pins: pins, groups: groups, tombstones: pruneTombstones(tombs, t) }
}

// Order-independent summary used to tell whether two states already match.
function fingerprint(state) {
  var pins = []
  var values = (state && state.pins) || []
  for (var i = 0; i < values.length; i++) {
    var n = normalizeEntry(values[i])
    if (n && n.type !== "image") pins.push(entryKey(n) + "|" + (n.group || "") + "|" + (n.label || "") + "|" + (n.at || 0))
  }
  pins.sort()
  var groups = (((state && state.groups) || []).map(function(g) { return g.id + "|" + g.name + "|" + (g.at || 0) })).sort()
  var tombs = []
  var t = (state && state.tombstones) || {}
  for (var k in t) tombs.push(k + "|" + t[k])
  tombs.sort()
  return JSON.stringify([pins, groups, tombs])
}

function makeSnapshot(pins, groups, tombstones, device) {
  var clean = []
  var values = Array.isArray(pins) ? pins : []
  for (var i = 0; i < values.length; i++) {
    var n = normalizeEntry(values[i])
    if (n && n.type !== "image") clean.push(n)
  }
  return { version: 2, device: String(device || ""), updated: Date.now(), pins: clean, groups: groups || [], tombstones: tombstones || {} }
}

// Drops unpinned history older than `days` (0 keeps everything) and trims to `maxEntries`.
function trimHistory(history, meta, pinned, days, maxEntries, now) {
  var t = now || Date.now()
  var values = Array.isArray(history) ? history : []
  var out = []
  for (var i = 0; i < values.length; i++) {
    var n = normalizeEntry(values[i])
    if (!n) continue
    var key = entryKey(n)
    var m = meta && meta[keyHash(key)]
    var old = days > 0 && m && m.t && (t - m.t) > days * 86400000
    if (old && !(pinned && pinned[key])) continue
    out.push(values[i])
  }
  var cap = Number(maxEntries) || 0
  return cap > 0 && out.length > cap ? out.slice(0, cap) : out
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeEntry: normalizeEntry,
    entryKey: entryKey,
    parseHistory: parseHistory,
    addEntry: addEntry,
    removeEntryAt: removeEntryAt,
    clearHistory: clearHistory,
    parseEntryJson: parseEntryJson,
    searchableText: searchableText,
    previewText: previewText,
    imagePreviewText: imagePreviewText,
    filePaths: filePaths,
    fileEntryText: fileEntryText,
    fullText: fullText,
    displayRows: displayRows,
    buildIndex: buildIndex,
    queryIndex: queryIndex,
    highlightTitle: highlightTitle,
    secretKind: secretKind,
    secretIsSure: secretIsSure,
    keyHash: keyHash,
    sha256hex: sha256hex,
    migrateKeys: migrateKeys,
    parseHistoryStrict: parseHistoryStrict,
    templateTokens: templateTokens,
    expandTemplate: expandTemplate,
    applyTransform: applyTransform,
    transformList: transformList,
    ago: ago,
    addPin: addPin,
    setPinGroup: setPinGroup,
    setPinLabel: setPinLabel,
    setPinFav: setPinFav,
    setPinTags: setPinTags,
    tagCounts: tagCounts,
    normalizeTags: normalizeTags,
    ungroupPins: ungroupPins,
    pinIndexByKey: pinIndexByKey,
    counts: counts,
    mergeArchive: mergeArchive,
    parseQuery: parseQuery,
    mergeSnapshots: mergeSnapshots,
    makeSnapshot: makeSnapshot,
    fingerprint: fingerprint,
    tombstoneFor: tombstoneFor,
    trimHistory: trimHistory,
    pinnedKeys: pinnedKeys,
    combinedRows: combinedRows
  }
}
