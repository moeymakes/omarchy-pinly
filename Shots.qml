import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "shots.js" as Shots

// The Screenshots tab: an inbox for the images in ~/Pictures, with categories, favorites,
// triage, text search (OCR) and safe deletion (system Trash). `host` is Pinly.qml's
// root item; it supplies theme colors, scaling helpers and the toast/undo plumbing.
Item {
  id: sh

  required property var host

  property var records: ({})
  property var cats: Shots.defaultCats()
  property bool storeOk: true
  property bool storeReady: false
  property string view: "inbox"
  property int sel: 0
  property bool triage: false
  property int skip: 0
  property bool searching: false
  property string query: ""
  property var list: []
  property var counts: ({ inbox: 0, all: 0, fav: 0, trash: 0, old: 0, byCat: ({}) })
  property var railItems: []
  property int thumbRev: 0
  property var undoStack: []
  property string lastApp: ""
  property real lastEventAt: 0
  property var metaQueue: []
  property var foundByPath: ({})
  property bool catEditOpen: false
  property string catEditMode: "new"
  property bool corruptCopied: false
  property string selHash: ""
  property bool rescanPending: false
  property var opQueue: []
  property var curOp: null

  readonly property string storePath: host.stateDir + "/clipboard-shots.json"
  readonly property string script: host.pluginDir + "/shots.sh"
  readonly property string thumbDir: Quickshell.env("HOME") + "/.cache/omarchy/clipboard-thumbs"
  readonly property var dirs: host.cfg.shotDirs || ["~/Pictures"]
  readonly property int oldDays: Number(host.cfg.shotOldDays) || 14
  readonly property var current: sel >= 0 && sel < list.length ? list[sel] : null

  readonly property int fTitle: host.fs(Style.font.title)
  readonly property int fCap: host.fs(Style.font.caption)
  readonly property int fHead: host.fs(Style.font.heading)
  readonly property int cell: host.sp(150)
  readonly property int columns: Math.max(1, Math.floor(grid.width / cell))

  // ---- store -------------------------------------------------------------
  function loadStore(raw, missing) {
    var r = Shots.parseStore(raw)
    sh.storeOk = missing ? true : r.ok
    if (!sh.storeOk && !sh.corruptCopied) {
      sh.corruptCopied = true
      Quickshell.execDetached(["cp", "-n", sh.storePath, sh.storePath + ".corrupt-" + Date.now()])
      host.statusMsg = "The screenshots file could not be read. Nothing will be saved until it is fixed; a copy was kept."
    }
    sh.records = r.store.records
    sh.cats = r.store.cats
    sh.storeReady = true
    sh.refresh()
    sh.startScan()
    sh.startWatch()
  }

  function saveSoon() { saveTimer.restart() }

  function saveNow() {
    if (!sh.storeOk || !sh.storeReady) return
    storeFile.setText(JSON.stringify({ version: 1, cats: sh.cats, records: sh.records }) + "\n")
    host.queueChmod()
  }

  function refresh() {
    sh.counts = Shots.counts(sh.records, sh.cats, sh.oldDays, Date.now())
    sh.list = Shots.select(sh.records, sh.cats, sh.view, sh.query, sh.oldDays, Date.now())
    var idx = -1
    for (var j = 0; j < sh.list.length; j++) if (sh.list[j].hash === sh.selHash) { idx = j; break }
    if (idx >= 0) sh.sel = idx
    else if (sh.sel >= sh.list.length) sh.sel = Math.max(0, sh.list.length - 1)
    sh.selHash = sh.list.length > 0 ? sh.list[sh.sel].hash : ""
    var items = [
      { kind: "view", id: "inbox", name: "Inbox", glyph: host.glyph(0xF06EB), count: sh.counts.inbox },
      { kind: "view", id: "all", name: "All shots", glyph: host.glyph(0xF02E9), count: sh.counts.all },
      { kind: "view", id: "fav", name: "Favorites", glyph: "★", count: sh.counts.fav },
      { kind: "sep", id: "", name: "Categories", glyph: "", count: 0 }
    ]
    for (var i = 0; i < sh.cats.length; i++) items.push({ kind: "cat", id: "cat:" + sh.cats[i].id, name: sh.cats[i].name, glyph: "", count: sh.counts.byCat[sh.cats[i].id] || 0, h: sh.cats[i].h, digit: i < 9 ? i + 1 : 0 })
    if (sh.counts.old > 0) items.push({ kind: "view", id: "old", name: "Old, unsorted", glyph: host.glyph(0xF0150), count: sh.counts.old })
    items.push({ kind: "view", id: "trash", name: "Trash", glyph: host.glyph(0xF01B4), count: sh.counts.trash })
    sh.railItems = items
  }

  function setSel(i) {
    sh.sel = i
    sh.selHash = i >= 0 && i < sh.list.length ? sh.list[i].hash : ""
  }

  function setView(id) {
    sh.view = id
    sh.sel = 0
    sh.selHash = ""
    sh.triage = false
    sh.refresh()
  }

  function viewIds() {
    var ids = ["inbox", "all", "fav"]
    for (var i = 0; i < sh.cats.length; i++) ids.push("cat:" + sh.cats[i].id)
    ids.push("trash")
    return ids
  }

  function cycleView(d) {
    var ids = sh.viewIds()
    var i = ids.indexOf(sh.view)
    sh.setView(ids[(Math.max(0, i) + d + ids.length) % ids.length])
  }

  function catById(id) {
    for (var i = 0; i < sh.cats.length; i++) if (sh.cats[i].id === id) return sh.cats[i]
    return null
  }

  function onOpened() {
    if (sh.storeReady && Date.now() - sh.lastScanAt > 5000) sh.startScan()
    sh.refresh()
  }

  property real lastScanAt: 0

  // ---- finding screenshots ----------------------------------------------
  function startScan() {
    if (!sh.storeReady || !host.cfgLoadedOnce) return
    if (scanProc.running || metaProc.running) { sh.rescanPending = true; return }
    sh.lastScanAt = Date.now()
    scanProc.command = [sh.script, "list"].concat(sh.dirs)
    scanProc.running = true
  }

  function handleList(text) {
    var found = []
    var lines = String(text || "").split("\n")
    sh.foundByPath = ({})
    for (var i = 0; i < lines.length; i++) {
      var p = lines[i].split("\t")
      if (p.length < 3) continue
      var f = { path: p[0], size: Number(p[1]), mtime: parseFloat(p[2]) }
      found.push(f)
      sh.foundByPath[f.path] = f
    }
    var plan = Shots.planScan(sh.records, found)
    // The same file back at its old path (restored from the file manager) leaves the Trash view.
    // A different file at that path does not.
    var recs = sh.records
    for (var h in recs) {
      var ff = recs[h].trashed ? sh.foundByPath[recs[h].path] : null
      if (ff && ff.size === recs[h].size && Math.floor(ff.mtime) === Math.floor(recs[h].mtime)) recs = Shots.setTrashed(recs, h, false)
    }
    sh.records = Shots.markGone(recs, plan.gone)
    sh.metaQueue = plan.need
    sh.metaNext()
  }

  function metaNext() {
    if (sh.metaQueue.length === 0) { sh.finishScan(); return }
    var batch = sh.metaQueue.slice(0, 20)
    sh.metaQueue = sh.metaQueue.slice(20)
    metaProc.command = [sh.script, "meta"].concat(batch.map(function(f) { return f.path }))
    metaProc.running = true
  }

  function handleMeta(text) {
    var items = []
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i]) continue
      try {
        var m = JSON.parse(lines[i])
        var f = sh.foundByPath[m.path]
        if (!f) continue
        // An identical copy at another path is not a new shot.
        var twin = sh.records[m.hash]
        if (twin && twin.path !== m.path && sh.foundByPath[twin.path] && !twin.trashed) continue
        m.size = f.size
        m.mtime = f.mtime
        items.push(m)
      } catch (e) {}
    }
    var app = (Date.now() - sh.lastEventAt < 12000) ? sh.lastApp : ""
    sh.records = Shots.upsert(sh.records, items, app, Date.now()).records
    sh.metaNext()
  }

  function finishScan() {
    sh.refresh()
    sh.saveNow()
    postTimer.restart()
    host.inboxCount = sh.counts.inbox
    if (sh.rescanPending) { sh.rescanPending = false; Qt.callLater(sh.startScan) }
  }

  function startWatch() {
    if (sh.storeReady && host.cfgLoadedOnce && !watchProc.running) watchProc.running = true
  }

  function noteApp(raw) {
    try {
      var j = JSON.parse(String(raw || "{}"))
      var cls = String(j["class"] || j.initialClass || "")
      if (cls.indexOf(".") >= 0) cls = cls.slice(cls.lastIndexOf(".") + 1)
      if (cls) sh.lastApp = cls.toLowerCase()
    } catch (e) {}
  }

  // ---- actions -----------------------------------------------------------
  // Trash and restore run one at a time, and a failure puts the record back as it was.
  function enqueueFileOp(args, onFail) {
    var q = sh.opQueue.slice()
    q.push({ args: args, fail: onFail })
    sh.opQueue = q
    sh.nextFileOp()
  }

  function nextFileOp() {
    if (fileProc.running || sh.opQueue.length === 0) return
    var q = sh.opQueue.slice()
    sh.curOp = q.shift()
    sh.opQueue = q
    fileProc.command = [sh.script].concat(sh.curOp.args)
    fileProc.running = true
  }

  function fileOpFinished(code) {
    var op = sh.curOp
    sh.curOp = null
    if (code !== 0 && op && op.fail) op.fail()
    sh.nextFileOp()
  }

  function pushUndo(rec) {
    var u = { hash: rec.hash, path: rec.path, cat: rec.cat || null, fav: !!rec.fav, trashed: !!rec.trashed }
    var s = sh.undoStack.slice(-30)
    s.push(u)
    sh.undoStack = s
    return u
  }

  function changed() {
    sh.refresh()
    sh.saveSoon()
    host.inboxCount = sh.counts.inbox
  }

  function trashRecord(hash, path) {
    sh.records = Shots.setTrashed(sh.records, hash, true, Date.now())
    sh.enqueueFileOp(["trash", path], function() {
      sh.records = Shots.setTrashed(sh.records, hash, false)
      sh.changed()
      host.showActionToast("Couldn't move that file to the Trash", null)
    })
  }

  function restoreRecord(hash, path) {
    sh.records = Shots.setTrashed(sh.records, hash, false)
    sh.enqueueFileOp(["restore", path], function() {
      sh.records = Shots.setTrashed(sh.records, hash, true, Date.now())
      sh.changed()
      host.showActionToast("Couldn't restore that file. It may be in the Trash still.", null)
    })
  }

  function setCategory(id) {
    var r = sh.current
    if (!r || r.trashed) return
    var u = sh.pushUndo(r)
    var next = r.cat === id ? null : id
    sh.records = Shots.setCat(sh.records, r.hash, next)
    var c = next ? sh.catById(next) : null
    sh.changed()
    host.showActionToast(c ? "Filed under " + c.name : "Category removed", function() { sh.undoEntry(u) })
  }

  function toggleFav() {
    var r = sh.current
    if (!r || r.trashed) return
    var u = sh.pushUndo(r)
    sh.records = Shots.setFav(sh.records, r.hash, !r.fav)
    sh.changed()
    host.showActionToast(r.fav ? "Removed from favorites" : "Kept as a favorite", function() { sh.undoEntry(u) })
  }

  function trashCurrent() {
    var r = sh.current
    if (!r || r.trashed) return
    var u = sh.pushUndo(r)
    sh.trashRecord(r.hash, r.path)
    sh.changed()
    host.showActionToast("Moved to the Trash", function() { sh.undoEntry(u) })
  }

  function restoreCurrent() {
    var r = sh.current
    if (!r || !r.trashed) return
    sh.pushUndo(r)
    sh.restoreRecord(r.hash, r.path)
    sh.changed()
    host.showActionToast("Restored", null)
  }

  // Undoes one specific action (a toast's Undo) or the latest one (the Z key).
  function undoEntry(u) {
    var r = sh.records[u.hash]
    sh.undoStack = sh.undoStack.filter(function(x) { return x !== u })
    if (!r) return
    var recs = Shots.setCat(sh.records, u.hash, u.cat)
    sh.records = Shots.setFav(recs, u.hash, u.fav)
    if (!!r.trashed !== u.trashed) {
      if (u.trashed) sh.trashRecord(u.hash, u.path)
      else sh.restoreRecord(u.hash, u.path)
    }
    sh.changed()
  }

  function undo() {
    if (sh.undoStack.length === 0) return
    sh.undoEntry(sh.undoStack[sh.undoStack.length - 1])
  }

  function pasteCurrent(copyOnly) {
    var r = sh.current
    if (!r || r.trashed) return
    var mime = /\.jpe?g$/i.test(r.path) ? "image/jpeg" : /\.webp$/i.test(r.path) ? "image/webp" : "image/png"
    host.opened = false
    Quickshell.execDetached(host.pasteEnv().concat([host.pluginDir + "/paste-file.sh"]).concat(copyOnly ? ["--copy-only"] : []).concat([mime, r.path]))
  }

  function annotateCurrent() {
    var r = sh.current
    if (!r || r.trashed) return
    host.opened = false
    Quickshell.execDetached([host.pluginDir + "/annotate.sh", r.path])
  }

  function textFromImage() {
    var r = sh.current
    if (!r) return
    host.opened = false
    Quickshell.execDetached([host.pluginDir + "/ocr.sh", r.path])
  }

  // ---- categories ---------------------------------------------------------
  function beginCatEdit(mode) {
    var c = sh.view.indexOf("cat:") === 0 ? sh.catById(sh.view.slice(4)) : null
    if (mode === "rename" && !c) return
    sh.catEditMode = mode
    sh.catEditOpen = true
    catInput.text = mode === "rename" ? c.name : ""
    Qt.callLater(function() { catInput.forceActiveFocus(); catInput.selectAll() })
  }

  function finishCatEdit(commit) {
    var name = catInput.text.trim()
    sh.catEditOpen = false
    if (commit && name) {
      var list = sh.cats.slice()
      if (sh.catEditMode === "rename") {
        var id = sh.view.slice(4)
        list = list.map(function(c) { return c.id === id ? { id: c.id, name: name, h: c.h, at: Date.now() } : c })
        sh.cats = list
        sh.refresh()
      } else {
        var hues = [10, 280, 50, 150, 220, 330, 90, 190]
        var nid = name.toLowerCase().replace(/[^a-z0-9]+/g, "-") + "-" + Date.now().toString(36)
        list.push({ id: nid, name: name, h: hues[list.length % hues.length], at: Date.now() })
        sh.cats = list
        sh.setView("cat:" + nid)
      }
      sh.saveSoon()
    }
    Qt.callLater(function() { host.refocus() })
  }

  function deleteCurrentCat() {
    if (sh.view.indexOf("cat:") !== 0) return
    var id = sh.view.slice(4)
    var c = sh.catById(id)
    if (!c) return
    var at = sh.cats.indexOf(c)
    var affected = []
    var recs = sh.records
    for (var h in recs) if (recs[h].cat === id) { affected.push(h); recs = Shots.setCat(recs, h, null) }
    sh.records = recs
    sh.cats = sh.cats.filter(function(x) { return x.id !== id })
    sh.setView("inbox")
    sh.saveSoon()
    host.showActionToast("Deleted category " + c.name + ". Its shots are back in the Inbox.", function() {
      var list = sh.cats.slice()
      list.splice(Math.min(at, list.length), 0, c)
      sh.cats = list
      var r2 = sh.records
      for (var i = 0; i < affected.length; i++) if (r2[affected[i]]) r2 = Shots.setCat(r2, affected[i], id)
      sh.records = r2
      sh.changed()
    })
  }

  // ---- keys ---------------------------------------------------------------
  // Returns true when the key was used. Plain letters are commands here; "/" starts a text search.
  function handleKey(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var alt = (event.modifiers & Qt.AltModifier) !== 0
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0
    var k = event.key

    if (k === Qt.Key_Escape) {
      if (sh.searching) { sh.searching = false; sh.query = ""; sh.refresh() }
      else if (sh.triage) sh.triage = false
      else if (sh.query !== "") { sh.query = ""; sh.refresh() }
      else host.close()
      return true
    }

    if (sh.searching) {
      if (k === Qt.Key_Return || k === Qt.Key_Enter) { sh.searching = false; return true }
      if (k === Qt.Key_Backspace) { sh.query = sh.query.slice(0, -1); sh.selHash = ""; sh.sel = 0; sh.refresh(); return true }
      if (ctrl && k === Qt.Key_U) { sh.query = ""; sh.selHash = ""; sh.sel = 0; sh.refresh(); return true }
      if (k === Qt.Key_Delete || k === Qt.Key_Tab || k === Qt.Key_Backtab) return true
      if (!ctrl && !alt && event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
        sh.query = sh.query + event.text
        sh.selHash = ""
        sh.sel = 0
        sh.refresh()
        return true
      }
    }

    if (ctrl && k === Qt.Key_F) { sh.searching = true; return true }
    if (ctrl && k === Qt.Key_N) { sh.beginCatEdit("new"); return true }
    if (ctrl && k === Qt.Key_O) { sh.textFromImage(); return true }
    if (ctrl && k === Qt.Key_Delete) { sh.deleteCurrentCat(); return true }
    if (ctrl || (alt && k !== Qt.Key_Return && k !== Qt.Key_Enter)) return false
    if (k === Qt.Key_F2) { sh.beginCatEdit("rename"); return true }

    if (k === Qt.Key_Return || k === Qt.Key_Enter) {
      if (sh.triage) return true
      if (alt) sh.annotateCurrent()
      else sh.pasteCurrent(shift)
      return true
    }
    if (k === Qt.Key_Tab) { sh.cycleView(1); return true }
    if (k === Qt.Key_Backtab) { sh.cycleView(-1); return true }

    var key = event.text ? event.text.toLowerCase() : ""

    // In triage the shot on screen is not list[sel], so every key goes through triageAct.
    if (sh.triage) {
      if (k >= Qt.Key_1 && k <= Qt.Key_9) { var tc = sh.cats[k - Qt.Key_1]; if (tc) sh.triageAct("cat", tc.id); return true }
      if (key === "f") { sh.triageAct("fav", null); return true }
      if (k === Qt.Key_Delete) { sh.triageAct("trash", null); return true }
      if (k === Qt.Key_Space) { sh.skip = sh.skip + 1; return true }
      if (key === "z") { sh.undo(); return true }
      if (key === "t") { sh.triage = false; return true }
      return true
    }

    if (key === "/") { sh.searching = true; return true }
    if (k >= Qt.Key_1 && k <= Qt.Key_9) {
      var c = sh.cats[k - Qt.Key_1]
      if (c) sh.setCategory(c.id)
      return true
    }
    if (k === Qt.Key_0) { var r0 = sh.current; if (r0 && r0.cat) sh.setCategory(r0.cat); return true }
    if (key === "f") { sh.toggleFav(); return true }
    if (key === "z") { sh.undo(); return true }
    if (key === "t") { sh.triage = true; sh.skip = 0; return true }
    if (key === "r") { sh.restoreCurrent(); return true }
    if (k === Qt.Key_Delete) { sh.trashCurrent(); return true }

    var n = sh.list.length
    if (n === 0) return false
    if (k === Qt.Key_Left) sh.setSel(Math.max(0, sh.sel - 1))
    else if (k === Qt.Key_Right) sh.setSel(Math.min(n - 1, sh.sel + 1))
    else if (k === Qt.Key_Up) sh.setSel(Math.max(0, sh.sel - sh.columns))
    else if (k === Qt.Key_Down) sh.setSel(Math.min(n - 1, sh.sel + sh.columns))
    else if (k === Qt.Key_Home) sh.setSel(0)
    else if (k === Qt.Key_End) sh.setSel(n - 1)
    else if (k === Qt.Key_PageUp) sh.setSel(Math.max(0, sh.sel - sh.columns * 3))
    else if (k === Qt.Key_PageDown) sh.setSel(Math.min(n - 1, sh.sel + sh.columns * 3))
    else return false
    grid.positionViewAtIndex(sh.sel, GridView.Contain)
    return true
  }

  // In triage the shot on screen is the sh.skip-th inbox item, wrapping around.
  readonly property var triageShot: {
    var rev = sh.records
    var items = Shots.select(sh.records, sh.cats, "inbox", "", sh.oldDays, Date.now())
    return { count: items.length, item: items.length > 0 ? items[sh.skip % items.length] : null }
  }

  function triageAct(kind, arg) {
    var it = sh.triageShot.item
    if (!it) return
    sh.pushUndo(it)
    if (kind === "cat") sh.records = Shots.setCat(sh.records, it.hash, arg)
    else if (kind === "fav") sh.records = Shots.setFav(sh.records, it.hash, true)
    else if (kind === "trash") sh.trashRecord(it.hash, it.path)
    sh.changed()
  }

  // ---- processes ------------------------------------------------------------
  FileView {
    id: storeFile
    path: sh.storePath
    atomicWrites: true
    printErrors: false
    onLoaded: sh.loadStore(text(), false)
    onLoadFailed: sh.loadStore("", true)
  }

  Timer { id: saveTimer; interval: 500; onTriggered: sh.saveNow() }

  Process {
    id: fileProc
    onExited: function(code, status) { sh.fileOpFinished(code) }
  }

  Timer { id: watchRestart; interval: 10000; onTriggered: sh.startWatch() }

  // Thumbnails and OCR read the saved store, so they start a moment after it is written.
  Timer {
    id: postTimer
    interval: 900
    onTriggered: {
      if (!thumbsProc.running) thumbsProc.running = true
      if (host.cfg.shotOcr !== false && !ocrProc.running) ocrProc.running = true
    }
  }

  Connections {
    target: host
    function onCfgLoadedOnceChanged() { sh.startScan(); sh.startWatch() }
  }

  Process {
    id: scanProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: sh.handleList(text) }
  }

  Process {
    id: metaProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: sh.handleMeta(text) }
  }

  Process {
    id: thumbsProc
    command: [sh.script, "thumbs"]
    stdout: SplitParser { onRead: function(line) { thumbTick.restart() } }
  }

  Timer { id: thumbTick; interval: 400; onTriggered: sh.thumbRev = sh.thumbRev + 1 }

  Process {
    id: ocrProc
    command: [sh.script, "ocr"]
    stdout: SplitParser {
      onRead: function(line) {
        try {
          var m = JSON.parse(line)
          sh.records = Shots.setOcr(sh.records, m.hash, m.text)
          ocrTick.restart()
        } catch (e) {}
      }
    }
  }

  Timer { id: ocrTick; interval: 3000; onTriggered: { sh.saveSoon(); if (sh.query !== "") sh.refresh() } }

  Process {
    id: hyprProc
    command: ["hyprctl", "activewindow", "-j"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: sh.noteApp(text) }
  }

  // Runs all the time (the plugin stays loaded) so shots taken while the overlay is closed are caught.
  Process {
    id: watchProc
    command: [sh.script, "watch"].concat(sh.dirs)
    onExited: watchRestart.restart()
    stdout: SplitParser {
      onRead: function(line) {
        sh.lastEventAt = Date.now()
        hyprProc.running = true
        rescanTimer.restart()
      }
    }
  }

  Timer { id: rescanTimer; interval: 900; onTriggered: sh.startScan() }

  // ---- interface -------------------------------------------------------------
  // Rail
  Rectangle {
    id: rail
    visible: !host.compactMode
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    width: host.railWidth
    color: "transparent"

    ListView {
      anchors.fill: parent
      anchors.margins: host.sp(8)
      anchors.rightMargin: host.sp(9)
      anchors.bottomMargin: host.sp(92)
      model: sh.railItems
      clip: true
      spacing: host.sp(2)
      boundsBehavior: Flickable.StopAtBounds

      delegate: Rectangle {
        id: ri
        required property var modelData
        readonly property bool isSep: modelData.kind === "sep"
        readonly property bool current: !isSep && modelData.id === sh.view
        width: ListView.view.width
        height: isSep ? host.sp(26) : host.sp(34)
        radius: host.innerRadius + host.sp(2)
        color: current ? host.selectedBackground : (riMouse.containsMouse && !isSep ? Qt.rgba(host.selectedBackground.r, host.selectedBackground.g, host.selectedBackground.b, 0.55) : "transparent")

        Text {
          visible: ri.isSep
          anchors.left: parent.left
          anchors.leftMargin: host.sp(8)
          anchors.bottom: parent.bottom
          anchors.bottomMargin: host.sp(3)
          text: ri.modelData.name
          textFormat: Text.PlainText
          color: host.muted
          font.family: host.fontFamily
          font.pixelSize: sh.fCap
        }

        Row {
          visible: !ri.isSep
          anchors.fill: parent
          anchors.leftMargin: host.sp(8)
          anchors.rightMargin: host.sp(8)
          spacing: host.sp(8)
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: host.sp(20)
            height: width
            radius: width / 2
            color: ri.modelData.kind === "cat" ? host.badgeBg(ri.modelData.h) : "transparent"
            Text {
              anchors.centerIn: parent
              text: ri.modelData.kind === "cat" ? ri.modelData.name.charAt(0).toUpperCase() : ri.modelData.glyph
              textFormat: Text.PlainText
              color: ri.modelData.kind === "cat" ? host.badgeFg(ri.modelData.h) : (ri.modelData.id === "inbox" && ri.modelData.count > 0 ? host.accent : host.muted)
              font.family: host.fontFamily
              font.pixelSize: ri.modelData.kind === "cat" ? sh.fCap : sh.fTitle
              font.bold: ri.modelData.kind === "cat"
            }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width - host.sp(20) - rcount.implicitWidth - rdigit.implicitWidth - parent.spacing * 3)
            text: ri.modelData.name
            textFormat: Text.PlainText
            color: ri.current ? host.selectedText : host.foreground
            font.family: host.fontFamily
            font.pixelSize: sh.fTitle
            elide: Text.ElideRight
          }
          Text {
            id: rcount
            anchors.verticalCenter: parent.verticalCenter
            text: ri.modelData.count
            color: ri.modelData.id === "inbox" && ri.modelData.count > 0 ? host.accent : host.muted
            font.family: host.fontFamily
            font.pixelSize: sh.fCap
          }
          Text {
            id: rdigit
            visible: ri.modelData.kind === "cat" && ri.modelData.digit > 0
            anchors.verticalCenter: parent.verticalCenter
            text: ri.modelData.kind === "cat" ? ri.modelData.digit : ""
            color: host.muted
            opacity: 0.8
            font.family: host.fontFamily
            font.pixelSize: sh.fCap
          }
        }

        MouseArea {
          id: riMouse
          anchors.fill: parent
          enabled: !ri.isSep
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: sh.setView(ri.modelData.id)
        }
      }
    }

    Column {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: host.sp(8)
      anchors.rightMargin: host.sp(9)
      spacing: host.sp(6)

      Rectangle {
        width: parent.width
        height: host.sp(34)
        radius: host.innerRadius
        color: newCatMouse.containsMouse ? host.selectedBackground : "transparent"
        border.width: 1
        border.color: host.line
        Text { anchors.centerIn: parent; text: host.glyph(0xF0415) + "  New category"; color: host.muted; font.family: host.fontFamily; font.pixelSize: sh.fTitle }
        MouseArea { id: newCatMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sh.beginCatEdit("new") }
      }

      Rectangle {
        width: parent.width
        height: host.sp(38)
        radius: host.innerRadius
        color: host.accent
        Text { anchors.centerIn: parent; text: host.glyph(0xF040A) + "  Triage inbox  T"; color: host.accentText; font.family: host.fontFamily; font.pixelSize: sh.fTitle; font.bold: true }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { sh.triage = true; sh.skip = 0 } }
      }
    }
  }

  // Compact: categories become a chip strip
  ListView {
    id: chips
    visible: host.compactMode
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: host.contentMargin
    anchors.rightMargin: host.contentMargin
    height: host.sp(40)
    orientation: ListView.Horizontal
    spacing: host.sp(6)
    clip: true
    model: sh.railItems.filter(function(x) { return x.kind !== "sep" })
    boundsBehavior: Flickable.StopAtBounds
    delegate: Rectangle {
      required property var modelData
      readonly property bool current: modelData.id === sh.view
      width: chipText.implicitWidth + host.sp(22)
      height: host.sp(32)
      radius: height / 2
      color: current ? host.accent : (chipMouse.containsMouse ? host.selectedBackground : host.surface)
      Text {
        id: chipText
        anchors.centerIn: parent
        text: modelData.name + "  " + modelData.count
        textFormat: Text.PlainText
        color: parent.current ? host.accentText : host.foreground
        font.family: host.fontFamily
        font.pixelSize: sh.fTitle
      }
      MouseArea { id: chipMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sh.setView(modelData.id) }
    }
  }

  // Grid
  Item {
    id: gridArea
    x: host.compactMode ? 0 : host.railWidth
    y: host.compactMode ? host.sp(48) : 0
    width: host.previewMode === "right" ? Math.round((parent.width - x) * 0.62) : parent.width - x
    height: (host.previewMode === "bottom" ? parent.height - host.sp(200) : parent.height) - y
    clip: true

    GridView {
      id: grid
      anchors.fill: parent
      anchors.margins: host.sp(10)
      cellWidth: Math.floor(width / Math.max(1, Math.floor(width / sh.cell)))
      cellHeight: Math.round(cellWidth * 0.78) + host.sp(30)
      model: sh.list
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      delegate: Item {
        id: card
        required property var modelData
        required property int index
        width: grid.cellWidth
        height: grid.cellHeight
        readonly property bool picked: index === sh.sel
        readonly property var cat: modelData.cat ? sh.catById(modelData.cat) : null

        Rectangle {
          anchors.fill: parent
          anchors.margins: host.sp(4)
          radius: host.innerRadius + host.sp(2)
          color: card.picked ? host.selectedBackground : "transparent"
          border.width: card.picked ? 2 : 0
          border.color: host.accent

          Rectangle {
            id: frame
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: host.sp(6)
            height: parent.height - host.sp(40)
            radius: host.innerRadius
            color: host.surface
            clip: true

            Image {
              id: thumb
              anchors.fill: parent
              source: Shots.fileUrl(sh.thumbDir + "/" + card.modelData.hash + ".webp")
              sourceSize.width: 360
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              cache: false
              smooth: true
              opacity: card.modelData.trashed ? 0.45 : 1
              Connections {
                target: sh
                function onThumbRevChanged() {
                  if (thumb.status === Image.Error || thumb.status === Image.Null) {
                    var s = Shots.fileUrl(sh.thumbDir + "/" + card.modelData.hash + ".webp")
                    thumb.source = ""
                    thumb.source = s
                  }
                }
              }
            }
            Text {
              visible: thumb.status !== Image.Ready
              anchors.centerIn: parent
              text: host.glyph(0xF02E9)
              color: host.muted
              font.family: host.fontFamily
              font.pixelSize: sh.fHead
            }
          }

          Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: host.sp(8)
            anchors.rightMargin: host.sp(8)
            anchors.bottomMargin: host.sp(7)
            spacing: host.sp(5)
            Rectangle {
              visible: card.cat !== null
              anchors.verticalCenter: parent.verticalCenter
              width: host.sp(9)
              height: width
              radius: width / 2
              color: card.cat ? host.badgeFg(card.cat.h) : "transparent"
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - (card.cat ? host.sp(14) : 0) - (card.modelData.fav ? host.sp(16) : 0)
              text: Qt.formatDateTime(new Date(card.modelData.at), "ddd hh:mm") + (card.modelData.app ? " · " + card.modelData.app : "")
              color: host.muted
              font.family: host.fontFamily
              font.pixelSize: sh.fCap
              elide: Text.ElideRight
            }
            Text {
              visible: card.modelData.fav
              anchors.verticalCenter: parent.verticalCenter
              text: "★"
              color: host.accent
              font.pixelSize: sh.fCap
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: sh.setSel(card.index)
            onDoubleClicked: { sh.setSel(card.index); sh.pasteCurrent(false) }
          }
        }
      }
    }

    Column {
      visible: sh.list.length === 0
      anchors.centerIn: parent
      width: parent.width - host.sp(40)
      spacing: host.sp(8)
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: sh.view === "inbox" && sh.query === "" ? "Inbox is clear" : sh.view === "trash" ? "Trash is empty" : sh.query !== "" ? "No screenshot matches" : "Nothing here yet"
        color: host.foreground
        font.family: host.fontFamily
        font.pixelSize: sh.fTitle
      }
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: sh.view === "inbox" && sh.query === "" ? "New screenshots land here. Press T to sort them one by one." : sh.query !== "" ? "Try fewer words, or Esc to clear the search." : "Shots you file or favorite show up in their own views."
        color: host.muted
        font.family: host.fontFamily
        font.pixelSize: sh.fCap
      }
    }
  }

  // Preview
  Item {
    id: prev
    visible: host.previewMode !== "off"
    x: host.previewMode === "right" ? gridArea.x + gridArea.width : (host.compactMode ? 0 : host.railWidth)
    y: host.previewMode === "right" ? 0 : gridArea.y + gridArea.height
    width: host.previewMode === "right" ? parent.width - x : parent.width - x
    height: host.previewMode === "right" ? parent.height : parent.height - y
    clip: true

    Rectangle {
      anchors.fill: parent
      anchors.topMargin: host.sp(8)
      anchors.leftMargin: host.previewMode === "right" ? host.sp(4) : host.sp(8)
      anchors.rightMargin: host.sp(10)
      anchors.bottomMargin: host.sp(8)
      radius: host.cornerRadius
      color: host.surface

      Column {
        visible: sh.current !== null
        anchors.fill: parent
        anchors.margins: host.sp(12)
        spacing: host.sp(8)

        Rectangle {
          width: parent.width
          height: Math.max(host.sp(60), parent.height - infoCol.height - actionsFlow.height - parent.spacing * 2)
          radius: host.innerRadius
          color: host.background
          clip: true
          Image {
            anchors.fill: parent
            anchors.margins: 2
            source: sh.current ? Shots.fileUrl(sh.current.path) : ""
            sourceSize.width: 900
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
          }
        }

        Column {
          id: infoCol
          width: parent.width
          spacing: host.sp(3)
          Text {
            width: parent.width
            text: sh.current ? Shots.baseName(sh.current.path) : ""
            color: host.foreground
            font.family: host.fontFamily
            font.pixelSize: sh.fCap
            font.weight: Font.Medium
            elide: Text.ElideMiddle
          }
          Text {
            width: parent.width
            text: sh.current ? Qt.formatDateTime(new Date(sh.current.at), "ddd d MMM hh:mm") + (sh.current.app ? " · " + sh.current.app : "") + " · " + sh.current.w + " × " + sh.current.h : ""
            color: host.muted
            font.family: host.fontFamily
            font.pixelSize: sh.fCap
            elide: Text.ElideRight
          }
          Text {
            visible: sh.current !== null && !!sh.current.ocr
            width: parent.width
            text: sh.current && sh.current.ocr ? "Text found: " + sh.current.ocr.slice(0, 110) : ""
            textFormat: Text.PlainText
            color: host.muted
            font.family: host.fontFamily
            font.pixelSize: sh.fCap
            wrapMode: Text.WrapAnywhere
            maximumLineCount: 2
            elide: Text.ElideRight
          }
        }

        Flow {
          id: actionsFlow
          width: parent.width
          spacing: host.sp(5)
          Repeater {
            model: sh.cats
            delegate: Rectangle {
              required property var modelData
              required property int index
              readonly property bool on: sh.current !== null && sh.current.cat === modelData.id
              height: host.sp(26)
              width: cn.implicitWidth + host.sp(22)
              radius: height / 2
              color: on ? host.badgeBg(modelData.h) : "transparent"
              border.width: 1
              border.color: on ? host.badgeFg(modelData.h) : host.line
              Text {
                id: cn
                anchors.centerIn: parent
                text: (index < 9 ? (index + 1) + "  " : "") + modelData.name
                textFormat: Text.PlainText
                color: parent.on ? host.badgeFg(modelData.h) : host.foreground
                font.family: host.fontFamily
                font.pixelSize: sh.fCap
              }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sh.setCategory(modelData.id) }
            }
          }
          Repeater {
            model: [
              { id: "copy", label: "Copy image  ↵", primary: true },
              { id: "fav", label: "Favorite  F", primary: false },
              { id: "annotate", label: "Annotate  ⌥↵", primary: false },
              { id: "trash", label: "Trash  Del", primary: false }
            ]
            delegate: Rectangle {
              required property var modelData
              height: host.sp(28)
              width: bl.implicitWidth + host.sp(22)
              radius: host.innerRadius
              color: modelData.primary ? host.accent : (bm.containsMouse ? host.selectedBackground : "transparent")
              border.width: modelData.primary ? 0 : 1
              border.color: host.line
              Text {
                id: bl
                anchors.centerIn: parent
                text: modelData.id === "trash" && sh.current && sh.current.trashed ? "Restore  R" : (modelData.id === "fav" && sh.current && sh.current.fav ? "Unfavorite  F" : modelData.label)
                color: modelData.primary ? host.accentText : host.foreground
                font.family: host.fontFamily
                font.pixelSize: sh.fCap
              }
              MouseArea {
                id: bm
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (modelData.id === "copy") sh.pasteCurrent(false)
                  else if (modelData.id === "fav") sh.toggleFav()
                  else if (modelData.id === "annotate") sh.annotateCurrent()
                  else if (sh.current && sh.current.trashed) sh.restoreCurrent()
                  else sh.trashCurrent()
                }
              }
            }
          }
        }
      }
    }
  }

  // Triage: one shot at a time
  Rectangle {
    id: triageView
    visible: sh.triage
    anchors.fill: parent
    color: host.background
    z: 5

    Column {
      anchors.centerIn: parent
      width: Math.min(parent.width - host.sp(40), host.sp(620))
      spacing: host.sp(12)

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: sh.triageShot.item ? "Triage · " + sh.triageShot.count + " left · " + Qt.formatDateTime(new Date(sh.triageShot.item.at), "ddd d MMM hh:mm") + (sh.triageShot.item.app ? " · " + sh.triageShot.item.app : "") : "Inbox is clear"
        color: host.muted
        font.family: host.fontFamily
        font.pixelSize: sh.fTitle
      }

      Rectangle {
        visible: sh.triageShot.item !== null
        width: parent.width
        height: Math.min(host.sp(320), triageView.height - host.sp(190))
        radius: host.cornerRadius
        color: host.surface
        clip: true
        Image {
          anchors.fill: parent
          anchors.margins: host.sp(6)
          source: sh.triageShot.item ? Shots.fileUrl(sh.triageShot.item.path) : ""
          sourceSize.width: 1100
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          cache: false
        }
      }

      Flow {
        visible: sh.triageShot.item !== null
        width: parent.width
        spacing: host.sp(6)
        Repeater {
          model: sh.cats
          delegate: Rectangle {
            required property var modelData
            required property int index
            height: host.sp(32)
            width: tl.implicitWidth + host.sp(26)
            radius: height / 2
            color: tm.containsMouse ? host.badgeBg(modelData.h) : "transparent"
            border.width: 1
            border.color: host.badgeFg(modelData.h)
            Text {
              id: tl
              anchors.centerIn: parent
              text: (index < 9 ? (index + 1) + "  " : "") + modelData.name
              textFormat: Text.PlainText
              color: host.badgeFg(modelData.h)
              font.family: host.fontFamily
              font.pixelSize: sh.fTitle
            }
            MouseArea { id: tm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sh.triageAct("cat", modelData.id) }
          }
        }
      }

      Row {
        spacing: host.sp(8)
        anchors.horizontalCenter: parent.horizontalCenter
        Repeater {
          model: [{ id: "fav", label: "Favorite  F" }, { id: "trash", label: "Trash  Del" }, { id: "skip", label: "Skip  Space" }, { id: "undo", label: "Undo  Z" }, { id: "done", label: "Done  Esc" }]
          delegate: Rectangle {
            required property var modelData
            visible: sh.triageShot.item !== null || modelData.id === "done"
            height: host.sp(30)
            width: ab.implicitWidth + host.sp(22)
            radius: host.innerRadius
            color: am.containsMouse ? host.selectedBackground : "transparent"
            border.width: 1
            border.color: host.line
            Text { id: ab; anchors.centerIn: parent; text: modelData.label; color: host.foreground; font.family: host.fontFamily; font.pixelSize: sh.fCap }
            MouseArea {
              id: am
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (modelData.id === "skip") sh.skip = sh.skip + 1
                else if (modelData.id === "undo") sh.undo()
                else if (modelData.id === "done") sh.triage = false
                else sh.triageAct(modelData.id, null)
              }
            }
          }
        }
      }
    }
  }

  // New or renamed category
  Rectangle {
    visible: sh.catEditOpen
    z: 8
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: host.sp(14)
    width: Math.min(parent.width - host.sp(32), host.sp(320))
    height: host.sp(44)
    radius: host.cornerRadius
    color: host.surface
    border.width: 2
    border.color: host.accent
    TextInput {
      id: catInput
      anchors.fill: parent
      anchors.leftMargin: host.sp(14)
      anchors.rightMargin: host.sp(14)
      verticalAlignment: TextInput.AlignVCenter
      color: host.foreground
      selectionColor: host.accent
      selectedTextColor: host.accentText
      font.family: host.fontFamily
      font.pixelSize: sh.fTitle
      maximumLength: 24
      clip: true
      onAccepted: sh.finishCatEdit(true)
      Keys.onEscapePressed: sh.finishCatEdit(false)
      Text {
        visible: catInput.text.length === 0
        anchors.fill: parent
        verticalAlignment: Text.AlignVCenter
        text: sh.catEditMode === "rename" ? "Rename category, then Enter" : "New category name, then Enter"
        color: host.muted
        font: catInput.font
      }
    }
  }
}
