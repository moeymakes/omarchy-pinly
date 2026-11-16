import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "ClipboardHistory.js" as ClipboardHistory

// Clipboard manager with pinned groups. Recording stays with the stock
// omarchy.clipboard plugin (it owns the wl-paste watchers and the history
// file); this overlay reads that file and keeps pins, groups and appearance
// in its own files under ~/.local/state/omarchy/.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool confirmOpen: false
  property string confirmKind: "clear"
  property var history: []
  property var pins: []
  property var groups: []
  property string lastGroup: ""
  property string view: "recent"
  property bool scopeAll: false
  property int elsewhereCount: 0
  property int displayRev: 0
  property bool settingsOpen: false
  property bool moveOpen: false
  property string moveKey: ""
  property bool groupEditOpen: false
  property string groupEditMode: "new"
  property string toastText: ""
  property bool toastUndoable: false
  property bool toastMovable: false
  property var toastSnapshot: null
  property var meta: ({})
  // Search index over history + pins + meta, rebuilt only when one of them changes.
  property var searchIndex: null
  onHistoryChanged: searchIndex = null
  onPinsChanged: searchIndex = null
  onMetaChanged: searchIndex = null
  property bool metaReady: false
  property bool historySeen: false
  property bool cfgLoadedOnce: false
  property string lastTopKey: ""
  property var pendingAppKeys: []
  property var markedKeys: []
  property bool revealSecrets: false
  property bool xformOpen: false
  property bool editing: false
  property bool editDiscardArmed: false
  property string editKey: ""
  property bool askOpen: false
  property string askRaw: ""
  property var askNames: []
  property var askVals: ({})
  property int askIdx: 0
  property bool askCopy: false
  property string syncStatus: ""
  property bool syncBusy: false
  property var tombstones: ({})
  property var toastTomb: null
  property string statusMsg: ""
  property bool pinsReady: false
  property bool selectMode: false
  property string subTab: "all"
  property var subTabs: []
  property bool cleanOpen: false
  property bool helpOpen: false
  property var cleanCounts: ({ old: 0, secrets: 0, big: 0 })
  property int lastMarkIndex: -1
  onMarkedKeysChanged: if (markedKeys.length === 0) lastMarkIndex = -1
  property bool bulkConfirmed: false
  property string tab: "clip"
  property int inboxCount: 0
  property var toastUndoFn: null
  property bool pinsOk: true
  property var stockHistory: []
  property var archive: []
  property bool stockLoaded: false
  property bool archiveReady: false
  property bool archiveOk: true
  property bool pinsBackedUp: false
  property bool pinsCorruptCopied: false
  property bool cfgBackedUp: false
  property bool cfgOk: true
  property bool historyOk: true
  property var bigPending: null
  property string exportDir: ""
  property string exportPending: ""
  property string exportJson: ""
  property var cfg: ({ theme: "omarchy", accent: "", preview: "right", density: "comfortable", corner: "soft", font: "mono", mode: "normal", openOn: "last", sizes: ({}), secretTtl: 10, mask: true, meta: true, rowScale: 100, paused: false, excludeApps: [], pasteMode: "shift-insert", keepDays: 0, maxEntries: 2000, syncFolder: "", syncPeer: "", importPath: "", tab: "clip", shotDirs: ["~/Pictures"], shotOcr: true, shotOldDays: 14 })
  property int dragW: 0
  property int dragScale: 0
  readonly property real rowScale: (dragScale > 0 ? dragScale : (Number(cfg.rowScale) || 100)) / 100
  readonly property real rowFont: 1
  property int dragH: 0

  // CLIPBOARD_PINS_STATE_DIR points the overlay at another folder (demos, screenshots, testing).
  property string stateDir: Quickshell.env("CLIPBOARD_PINS_STATE_DIR") || (Quickshell.env("HOME") + "/.local/state/omarchy")
  property string historyPath: stateDir + "/clipboard-history.json"
  property string pinsPath: stateDir + "/clipboard-pins.json"
  property string cfgPath: stateDir + "/clipboard-pins-settings.json"
  property string archivePath: stateDir + "/clipboard-archive.json"
  property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, ""))

  readonly property var hues: [250, 150, 20, 300, 90, 200]
  readonly property var presets: ({
    coppernight: { bg: "#1b1614", fg: "#efe6df", sel: "#3a2a22", selfg: "#ffe1cb", accent: "#e08a4b", border: "#3a302a" },
    graphite: { bg: "#16181b", fg: "#e8eaed", sel: "#2a3038", selfg: "#ffffff", accent: "#5aa9ff", border: "#2d3238" },
    paper: { bg: "#fbfbfc", fg: "#1a1d21", sel: "#e2e7f0", selfg: "#0e1116", accent: "#2f5bd9", border: "#d4d8de" },
    nord: { bg: "#2e3440", fg: "#eceff4", sel: "#3b4252", selfg: "#ffffff", accent: "#88c0d0", border: "#434c5e" },
    terminal: { bg: "#090c09", fg: "#c8f2c8", sel: "#16301a", selfg: "#eaffea", accent: "#4be04b", border: "#1d3a20" }
  })
  readonly property var themeChoices: [
    { id: "omarchy", name: "Omarchy", bg: "", sel: "", accent: "" },
    { id: "coppernight", name: "Coppernight", bg: "#1b1614", sel: "#3a2a22", accent: "#e08a4b" },
    { id: "graphite", name: "Graphite", bg: "#16181b", sel: "#2a3038", accent: "#5aa9ff" },
    { id: "paper", name: "Paper", bg: "#fbfbfc", sel: "#e2e7f0", accent: "#2f5bd9" },
    { id: "nord", name: "Nord", bg: "#2e3440", sel: "#3b4252", accent: "#88c0d0" },
    { id: "terminal", name: "Terminal", bg: "#090c09", sel: "#16301a", accent: "#4be04b" }
  ]
  readonly property var accentChoices: ["#e08a4b", "#5aa9ff", "#4be04b", "#d96aa8", "#b69cff", "#f2c94c"]
  readonly property var settingSections: [
    { key: "shotOcr", label: "Read text inside screenshots (OCR)", opts: [{ v: true, l: "On" }, { v: false, l: "Off" }] },
    { key: "shotOldDays", label: "Call unsorted screenshots old after", opts: [{ v: 7, l: "7 days" }, { v: 14, l: "14 days" }, { v: 30, l: "30 days" }] },
    { key: "paused", label: "Private mode (don't keep new copies)", opts: [{ v: false, l: "Off" }, { v: true, l: "On" }] },
    { key: "pasteMode", label: "Paste method", opts: [{ v: "shift-insert", l: "Shift+Insert" }, { v: "ctrl-v", l: "Ctrl+V" }, { v: "ctrl-shift-v", l: "Ctrl+Shift+V" }, { v: "copy", l: "Copy only" }] },
    { key: "keepDays", label: "Keep history for", opts: [{ v: 0, l: "Forever" }, { v: 1, l: "1 day" }, { v: 7, l: "1 week" }, { v: 30, l: "1 month" }] },
    { key: "maxEntries", label: "Keep at most (history)", opts: [{ v: 100, l: "100" }, { v: 500, l: "500" }, { v: 2000, l: "2,000" }, { v: 5000, l: "5,000" }, { v: 10000, l: "10,000" }] },
    { key: "secretTtl", label: "Auto-delete secrets after", opts: [{ v: 0, l: "Never" }, { v: 1, l: "1 min" }, { v: 10, l: "10 min" }, { v: 60, l: "1 hour" }] },
    { key: "mask", label: "Secrets in the list", opts: [{ v: true, l: "Hide" }, { v: false, l: "Show" }] },
    { key: "meta", label: "Time and app on rows", opts: [{ v: true, l: "Show" }, { v: false, l: "Hide" }] },
    { key: "mode", label: "Window size", opts: [{ v: "compact", l: "Compact" }, { v: "normal", l: "Normal" }, { v: "full", l: "Full" }] },
    { key: "openOn", label: "Open on", opts: [{ v: "last", l: "Last group" }, { v: "recent", l: "Recent" }] },
    { key: "preview", label: "Preview pane", opts: [{ v: "right", l: "Right" }, { v: "bottom", l: "Bottom" }, { v: "off", l: "Off" }] },
    { key: "corner", label: "Corners", opts: [{ v: "sharp", l: "Sharp" }, { v: "soft", l: "Soft" }, { v: "round", l: "Round" }] },
    { key: "font", label: "Text", opts: [{ v: "mono", l: "Menu font" }, { v: "sans", l: "Sans" }] }
  ]

  // Colors. "omarchy" follows the active Omarchy theme's [menu] tokens, same
  // as the stock manager; the presets are fixed palettes.
  readonly property bool systemTheme: !presets[cfg.theme]
  property color background: systemTheme ? Color.menu.background : presets[cfg.theme].bg
  property color foreground: systemTheme ? Color.menu.text : presets[cfg.theme].fg
  property color border: systemTheme ? Color.menu.border : presets[cfg.theme].border
  // Read on open, not at startup: the theme singleton is not ready when the plugin
  // loads, and a failed read leaves an invalid colour, which paints solid black.
  readonly property color scrim: {
    var m = root.opened ? Color.menu : null
    return m && m.scrim !== undefined ? m.scrim : Qt.rgba(0, 0, 0, 0.5)
  }
  property color selectedBackground: systemTheme ? Color.menu.selectedBackground : presets[cfg.theme].sel
  property color selectedText: systemTheme ? Color.menu.selectedText : presets[cfg.theme].selfg
  property color accent: cfg.accent ? cfg.accent : (systemTheme ? Color.menu.selectedText : presets[cfg.theme].accent)
  readonly property color accentText: accent.hslLightness > 0.55 ? "#101010" : "#ffffff"
  readonly property bool isDark: background.hslLightness < 0.5
  readonly property color surface: Qt.tint(background, Qt.rgba(foreground.r, foreground.g, foreground.b, 0.05))
  readonly property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.62)
  readonly property color line: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.14)
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, root.sp(2)))
  readonly property int cornerRadius: cfg.corner === "sharp" ? root.sp(4) : cfg.corner === "round" ? root.sp(20) : Math.max(Style.cornerRadius, root.sp(12))
  readonly property int innerRadius: Math.max(3, Math.round(cornerRadius * 0.75))
  property string fontFamily: cfg.font === "sans" ? "sans-serif" : Style.font.menuFamily
  property int contentMargin: root.sc(Style.spacing.panelPadding)
  property int headerHeight: Math.max(root.sp(34), root.fs(Style.font.title) + root.sc(Style.spacing.controlPaddingY) * 2)
  property int contentSpacing: root.sc(Style.spacing.md)
  readonly property real unit: Style.space(100) / 100
  readonly property var modeDefaults: ({ compact: { w: 520, h: 470 }, normal: { w: 960, h: 620 }, full: { w: 1360, h: 880 } })
  readonly property bool compactMode: cfg.mode === "compact"
  readonly property string previewMode: compactMode ? "off" : cfg.preview
  readonly property int maxW: panel.width - Style.gapsOut * 2
  readonly property int maxH: panel.height - Style.gapsOut * 2
  readonly property int minW: Math.round((compactMode ? 380 : 640) * unit)
  readonly property int minH: Math.round((compactMode ? 300 : 420) * unit)
  property int cardWidth: Math.max(Math.min(dragW > 0 ? dragW : sizeFor(cfg.mode, "w"), maxW), Math.min(minW, maxW))
  property int cardHeight: Math.max(Math.min(dragH > 0 ? dragH : sizeFor(cfg.mode, "h"), maxH), Math.min(minH, maxH))
  property int railWidth: root.sp(196)
  property int railW: compactMode ? 0 : railWidth
  property int topInset: compactMode ? root.sp(48) : 0
  property int rowHeight: Math.max(root.sp(16), Math.round(Math.max(root.sp(50), root.fs(Style.font.body) + root.fs(Style.font.caption) + root.sc(Style.spacing.rowPaddingX) * 2)))
  readonly property int twoLineH: Math.round((root.fs(Style.font.title) + root.fs(Style.font.caption)) * rowFont * 1.3 + root.sp(8))
  property int historyLimit: 300

  // Compact mode scales the whole interface down so more rows fit.
  readonly property real k: rowScale * (compactMode ? 0.8 : 1)
  function sc(v) { return Math.round(v * root.k) }
  function sp(n) { return Math.round(Style.space(n) * root.k) }
  function rf(v) { return Math.max(8, Math.round(root.fs(v) * root.rowFont)) }
  function rs(n) { return Math.round(root.sp(n) * Math.min(1, root.rowFont)) }
  function nudgeDensity(delta) {
    var v = Math.max(40, Math.min(180, (Number(root.cfg.rowScale) || 100) + delta))
    root.setCfg("rowScale", v)
  }
  function fs(v) { return Math.max(9, Math.round(v * root.k)) }

  readonly property var activeRow: {
    var rev = root.displayRev
    return displayModel.count > 0 && root.selectedIndex >= 0 && root.selectedIndex < displayModel.count ? displayModel.get(root.selectedIndex) : null
  }

  function glyph(cp) { return String.fromCodePoint(cp) }
  function kindGlyph(kind) {
    if (kind === "image") return glyph(0xF02E9)
    if (kind === "file") return glyph(0xF0214)
    if (kind === "url") return glyph(0xF0339)
    if (kind === "code") return glyph(0xF0169)
    if (kind === "color") return glyph(0xF03D8)
    if (kind === "template") return "{}"
    return glyph(0xF0262)
  }

  function groupById(id) {
    for (var i = 0; i < root.groups.length; i++) if (root.groups[i].id === id) return root.groups[i]
    return null
  }
  function groupName(id) {
    if (id === "recent") return "Recent"
    if (id === "all") return "All pinned"
    if (id === "frequent") return "Frequent"
    var g = groupById(id)
    return g ? g.name : "No group"
  }
  function badgeBg(h) { return Qt.hsla(h / 360, 0.55, root.isDark ? 0.34 : 0.82, 1) }
  function badgeFg(h) { return Qt.hsla(h / 360, 0.75, root.isDark ? 0.86 : 0.28, 1) }
  function groupHue(id) { var g = groupById(id); return g ? g.h : 0 }
  function groupLetter(id) { var g = groupById(id); return g ? g.name.charAt(0).toUpperCase() : "?" }

  // ---- lifecycle -------------------------------------------------------
  function open(payloadJson) {
    if (root.tab === "shots") shotsTab.onOpened()
    if (root.cfg.syncFolder) syncFile.reload()
    if (root.cfg.openOn === "recent") root.view = "recent"
    else if (root.view !== "recent" && root.view !== "all" && root.view !== "frequent" && !root.groupById(root.view)) root.view = "recent"
    root.opened = true
    root.revealSecrets = false
    root.markedKeys = []
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.moveOpen = false
    root.groupEditOpen = false
    root.editing = false
    root.disarmPointer()
    root.rebuildDisplay()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.cancelConfirm()
    shotsTab.triage = false
    shotsTab.searching = false
    shotsTab.catEditOpen = false
    root.selectMode = false
    root.helpOpen = false
    root.cleanOpen = false
    root.moveOpen = false
    root.xformOpen = false
    root.editing = false
    root.askOpen = false
    root.groupEditOpen = false
    root.markedKeys = []
    root.revealSecrets = false
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  // ---- persistence -----------------------------------------------------
  // The stock plugin keeps the last 300 copies. This plugin keeps a longer list of its own
  // (the archive) and shows that; the stock file is only read, and pruned when you delete.
  function loadHistory(raw, missing) {
    var r = ClipboardHistory.parseHistoryStrict(raw)
    root.historyOk = missing ? true : r.ok
    root.stockHistory = r.list
    root.stockLoaded = true
    root.mergeArchive()
    if (root.opened) root.rebuildDisplay()
  }

  function loadArchive(raw, missing) {
    var r = ClipboardHistory.parseHistoryStrict(raw)
    root.archiveOk = missing ? true : r.ok
    if (!root.archiveOk) {
      Quickshell.execDetached(["cp", "-n", root.archivePath, root.archivePath + ".corrupt-" + Date.now()])
      root.statusMsg = "The history archive could not be read; a copy was kept and the archive will not be written."
    }
    root.archive = r.list
    root.archiveReady = true
    root.mergeArchive()
    if (root.opened) root.rebuildDisplay()
  }

  // Waits for the settings: the archive size cap and the secret timer come from them, and the
  // built-in defaults (2,000 entries, 10 minutes) must never trim or delete data before they load.
  function mergeArchive() {
    if (!root.archiveReady || !root.stockLoaded || !root.cfgLoadedOnce) return
    var cap = Number(root.cfg.maxEntries) || 2000
    var merged = ClipboardHistory.mergeArchive(root.stockHistory, root.archive, cap)
    var changed = JSON.stringify(merged) !== JSON.stringify(root.archive)
    root.archive = merged
    root.history = merged
    if (changed && root.archiveOk && root.cfgOk) root.writeArchive()
    root.ingestHistory()
  }

  function writeArchive() {
    archiveFile.setText(JSON.stringify(root.history) + "\n")
    chmodTimer.restart()
  }

  // Called after entries are removed from the list: writes the archive and removes the same
  // entries from the stock plugin's file.
  function saveHistory() {
    if (!root.archiveOk) return
    root.archive = root.history
    root.writeArchive()
    if (root.historyOk && root.stockHistory.length > 0) {
      var keep = {}
      for (var i = 0; i < root.history.length; i++) keep[root.entryKeyOf(root.history[i])] = true
      var pruned = root.stockHistory.filter(function(e) { return keep[root.entryKeyOf(e)] })
      if (pruned.length !== root.stockHistory.length) {
        root.stockHistory = pruned
        historyFile.setText(JSON.stringify(pruned, null, 2) + "\n")
      }
    }
  }

  // A missing file is a fresh start. An empty or corrupt one is never treated as
  // "no pins": the file is kept aside and writes are blocked until it parses again.
  function loadPins(raw, missing) {
    var r = ClipboardHistory.parseHistoryStrict(raw)
    root.pinsOk = missing ? true : r.ok
    if (!root.pinsOk) {
      if (!root.pinsCorruptCopied) { root.pinsCorruptCopied = true; Quickshell.execDetached(["cp", "-n", root.pinsPath, root.pinsPath + ".corrupt-" + Date.now()]) }
      root.statusMsg = "The pins file could not be read. Nothing will be saved until it is fixed; a copy was kept."
    } else if (!missing && r.list.length > 0 && !root.pinsBackedUp) {
      root.pinsBackedUp = true
      Quickshell.execDetached(["cp", "-f", root.pinsPath, root.pinsPath + ".bak"])
    }
    root.pins = r.list
    root.pinsReady = true
    if (root.opened) root.rebuildDisplay()
  }

  function savePins() {
    if (!root.pinsOk) return
    pinsFile.setText(JSON.stringify(root.pins, null, 2) + "\n")
    chmodTimer.restart()
    root.queueSyncPush()
  }

  // Remembers that a pin was removed so a synced machine removes it too.
  function removePinAt(index) {
    var e = root.pins[index]
    if (e) root.tombstones = ClipboardHistory.tombstoneFor(root.tombstones, root.entryKeyOf(e), Date.now())
    root.pins = ClipboardHistory.removeEntryAt(root.pins, index)
  }

  function seedGroups() {
    root.groups = [{ id: "dev", name: "Dev", h: 250 }, { id: "writing", name: "Writing", h: 150 }, { id: "links", name: "Links", h: 20 }]
    root.lastGroup = "dev"
  }

  function loadCfg(raw) {
    root.cfgOk = true
    try {
      if (String(raw || "").trim() === "") throw new Error("empty settings file")
      var parsed = JSON.parse(String(raw))
      if (parsed.cfg && typeof parsed.cfg === "object") {
        var next = Object.assign({}, root.cfg)
        for (var k in parsed.cfg) next[k] = parsed.cfg[k]
        if (next.maxEntries === 300) next.maxEntries = 2000
        if (["clip", "links", "shots"].indexOf(next.tab) >= 0) root.tab = next.tab
        root.cfg = next
      }
      if (Array.isArray(parsed.groups)) root.groups = parsed.groups
      else root.seedGroups()
      root.lastGroup = typeof parsed.lastGroup === "string" ? parsed.lastGroup : ""
      if (!root.cfgLoadedOnce && root.cfg.openOn !== "recent" && typeof parsed.view === "string" && parsed.view) root.view = parsed.view
      if (!root.cfgBackedUp) {
        root.cfgBackedUp = true
        Quickshell.execDetached(["cp", "-f", root.cfgPath, root.cfgPath + ".bak"])
      }
    } catch (e) {
      // Unreadable settings: keep the file aside, run on defaults, and never overwrite it.
      root.cfgOk = false
      Quickshell.execDetached(["cp", "-n", root.cfgPath, root.cfgPath + ".corrupt-" + Date.now()])
      root.statusMsg = "The settings file could not be read. Changes will not be saved until it is fixed; a copy was kept."
      root.seedGroups()
    }
    try {
      var tp = JSON.parse(String(raw || "{}")).tombstones
      if (tp && typeof tp === "object") root.tombstones = ClipboardHistory.migrateKeys(tp)
    } catch (e2) {}
    root.cfgLoadedOnce = true
    root.mergeArchive()
    if (root.opened) root.rebuildDisplay()
  }

  function saveCfg() {
    if (!root.cfgOk) return
    chmodTimer.restart()
    cfgFile.setText(JSON.stringify({ cfg: root.cfg, groups: root.groups, lastGroup: root.lastGroup, view: root.view, tombstones: root.tombstones }, null, 2) + "\n")
    root.queueSyncPush()
  }

  function setCfg(key, value) {
    var next = Object.assign({}, root.cfg)
    next[key] = value
    root.cfg = next
    root.saveCfg()
  }

  function resetCfg() {
    root.cfg = { theme: "omarchy", accent: "", preview: "right", density: "comfortable", corner: "soft", font: "mono", mode: root.cfg.mode, openOn: root.cfg.openOn, sizes: root.cfg.sizes, secretTtl: root.cfg.secretTtl, mask: root.cfg.mask, meta: root.cfg.meta, rowScale: 100, paused: root.cfg.paused, excludeApps: root.cfg.excludeApps, pasteMode: root.cfg.pasteMode, keepDays: root.cfg.keepDays, maxEntries: root.cfg.maxEntries, syncFolder: root.cfg.syncFolder, syncPeer: root.cfg.syncPeer, importPath: root.cfg.importPath, tab: root.cfg.tab, shotDirs: root.cfg.shotDirs, shotOcr: root.cfg.shotOcr, shotOldDays: root.cfg.shotOldDays }
    root.saveCfg()
  }

  // ---- window mode and size ---------------------------------------------
  function setMode(m) {
    if (m === root.cfg.mode) return
    root.dragW = 0
    root.dragH = 0
    root.setCfg("mode", m)
  }

  function cycleMode(delta) {
    var order = ["compact", "normal", "full"]
    var i = order.indexOf(root.cfg.mode)
    root.setMode(order[Math.max(0, Math.min(order.length - 1, i + delta))])
  }

  function commitSize() {
    var sizes = Object.assign({}, root.cfg.sizes || {})
    sizes[root.cfg.mode] = { w: Math.round(root.cardWidth / root.unit), h: Math.round(root.cardHeight / root.unit) }
    root.setCfg("sizes", sizes)
    root.dragW = 0
    root.dragH = 0
  }

  function resetSize() {
    var sizes = Object.assign({}, root.cfg.sizes || {})
    delete sizes[root.cfg.mode]
    root.dragW = 0
    root.dragH = 0
    root.setCfg("sizes", sizes)
  }

  function sizeFor(mode, axis) {
    var s = root.cfg.sizes && root.cfg.sizes[mode]
    var v = s && s[axis] ? s[axis] : root.modeDefaults[mode][axis]
    return Math.round(v * root.unit)
  }

  // ---- display model ---------------------------------------------------
  function currentIndex() {
    if (!root.searchIndex) root.searchIndex = ClipboardHistory.buildIndex(root.history, root.pins, root.meta)
    return root.searchIndex
  }

  // filterOnly: only the search text changed, so the rail and sub-tab counts are still right.
  function rebuildDisplay(filterOnly) {
    root.lastMarkIndex = -1   // row positions are about to change
    if (root.subTab.indexOf("tag:") === 0) {
      var ex = ClipboardHistory.tagCounts(root.pins).tags
      if (!ex.some(function(x) { return "tag:" + x.tag === root.subTab })) root.subTab = "all"
    }
    var res = ClipboardHistory.queryIndex(root.currentIndex(), (root.tab === "links" ? "is:url " : "") + root.filterText, 50, root.view, root.scopeAll, root.groupNameMap(), root.subTab)
    root.elsewhereCount = res.elsewhere

    displayModel.clear()
    for (var i = 0; i < res.rows.length; i++) {
      var row = res.rows[i]
      displayModel.append({
        entryType: row.entryType,
        fullText: row.fullText,
        previewText: row.previewText,
        subtitle: row.subtitle,
        previewImage: row.previewImage ? Util.fileUrl(row.previewImage) : "",
        path: row.path,
        mime: row.mime,
        label: row.label,
        group: row.group,
        kind: row.kind,
        swatch: row.swatch,
        fav: row.fav,
        tagsText: row.tagsText,
        key: row.key,
        app: row.app,
        ts: row.ts,
        seen: row.seen,
        secret: row.secret,
        historyIndex: row.index,
        pinned: row.pinned,
        pinIndex: row.pinIndex
      })
    }

    if (filterOnly !== true) root.rebuildNav()
    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0
    if (root.editing) {
      var at = -1
      for (var e = 0; e < displayModel.count; e++) if (displayModel.get(e).key === root.editKey) { at = e; break }
      if (at < 0) root.editing = false
      else {
        selectedIndex = at
        Qt.callLater(function() { if (root.editing) editInput.forceActiveFocus() })
      }
    }
    root.displayRev = root.displayRev + 1

    Qt.callLater(function() {
      if (displayModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  // The footer hints double as buttons: each runs what its key does.
  function footerAction(a) {
    var sel = root.selectedIndex
    if (a === "help") root.helpOpen = !root.helpOpen
    else if (a === "paste") { if (displayModel.count > 0) root.activateIndex(sel) }
    else if (a === "copy") { if (displayModel.count > 0) root.copyIndex(sel) }
    else if (a === "pin") root.pinSelected()
    else if (a === "move") root.openMove()
    else if (a === "fav") root.toggleFav()
    else if (a === "transform") root.openXform()
    else if (a === "cleanup") root.openCleanup()
    else if (a === "select") { root.selectMode = !root.selectMode; if (!root.selectMode) root.markedKeys = [] }
    else if (a === "reveal") root.revealSecrets = !root.revealSecrets
    else if (a === "group") root.cycleView(1)
    else if (a === "size") root.cycleMode(1)
    else if (a === "settings") root.settingsOpen = !root.settingsOpen
    else if (a === "tab") root.cycleTab(1)
    else if (a === "shotPaste") shotsTab.pasteCurrent(false)
    else if (a === "shotFav") { if (shotsTab.triage) shotsTab.triageAct("fav", null); else shotsTab.toggleFav() }
    else if (a === "shotTrash") { if (shotsTab.triage) shotsTab.triageAct("trash", null); else shotsTab.trashCurrent() }
    else if (a === "shotTriage") { shotsTab.triage = !shotsTab.triage; shotsTab.skip = 0 }
    else if (a === "shotSearch") shotsTab.searching = true
    else if (a === "shotUndo") shotsTab.undo()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function setSubTab(id) {
    root.subTab = id
    root.selectedIndex = 0
    root.rebuildDisplay()
  }

  function cycleSubTab(d) {
    if (root.view !== "all" || root.subTabs.length === 0) return
    var i = 0
    for (var k = 0; k < root.subTabs.length; k++) if (root.subTabs[k].id === root.subTab) i = k
    root.setSubTab(root.subTabs[(i + d + root.subTabs.length) % root.subTabs.length].id)
  }

  // Ctrl+D: star the selected entry. An entry that is not pinned yet is pinned first.
  function toggleFav() {
    var row = root.activeRow
    if (!row) return
    var snapshot = root.pins.slice()
    if (!row.pinned) {
      var entry = root.history[row.historyIndex]
      if (!entry) return
      root.pins = ClipboardHistory.setPinFav(ClipboardHistory.addPin(root.pins, entry, root.lastGroup), 0, true)
      root.savePins()
      root.rebuildDisplay()
      root.showToast("Pinned and added to favorites", true, false, snapshot)
      return
    }
    root.pins = ClipboardHistory.setPinFav(root.pins, row.pinIndex, !row.fav)
    root.savePins()
    root.rebuildDisplay()
    root.showToast(row.fav ? "Removed from favorites" : "Added to favorites", true, false, snapshot)
  }

  function addTagsToCurrent(text) {
    var row = root.activeRow
    if (!row || !row.pinned) return
    var cur = row.tagsText ? row.tagsText.split(" ") : []
    root.pins = ClipboardHistory.setPinTags(root.pins, row.pinIndex, cur.concat(ClipboardHistory.normalizeTags(text)))
    root.savePins()
    root.rebuildDisplay()
  }

  function removeTagFromCurrent(tag) {
    var row = root.activeRow
    if (!row || !row.pinned) return
    var cur = row.tagsText ? row.tagsText.split(" ") : []
    root.pins = ClipboardHistory.setPinTags(root.pins, row.pinIndex, cur.filter(function(t) { return t !== tag }))
    root.savePins()
    root.rebuildDisplay()
  }

  function rebuildNav() {
    var tc = ClipboardHistory.tagCounts(root.pins)
    var strip = [{ id: "all", label: "All", count: tc.total }, { id: "fav", label: "★ Favorites", count: tc.favs }]
    for (var t = 0; t < tc.tags.length; t++) strip.push({ id: "tag:" + tc.tags[t].tag, label: "#" + tc.tags[t].tag, count: tc.tags[t].count })
    root.subTabs = strip
    var c = ClipboardHistory.counts(root.history, root.pins, root.meta)
    navModel.clear()
    navModel.append({ kind: "recent", gid: "recent", name: "Recent", h: 0, count: c.recent, digit: 1 })
    navModel.append({ kind: "all", gid: "all", name: "All pinned", h: 0, count: c.all, digit: 2 })
    navModel.append({ kind: "frequent", gid: "frequent", name: "Frequent", h: 0, count: c.frequent, digit: 3 })
    navModel.append({ kind: "sep", gid: "", name: "Groups", h: 0, count: 0, digit: 0 })
    for (var i = 0; i < root.groups.length; i++) {
      var g = root.groups[i]
      navModel.append({ kind: "group", gid: g.id, name: g.name, h: g.h, count: c.byGroup[g.id] || 0, digit: i + 4 <= 9 ? i + 4 : 0 })
    }
  }

  function groupNameMap() {
    var m = {}
    for (var i = 0; i < root.groups.length; i++) m[root.groups[i].id] = root.groups[i].name
    return m
  }

  function navIds() {
    var ids = ["recent", "all", "frequent"]
    for (var i = 0; i < root.groups.length; i++) ids.push(root.groups[i].id)
    return ids
  }

  function setView(id) {
    if (!id) return
    root.view = id
    if (root.groupById(id)) root.lastGroup = id
    root.saveCfg()
    root.selectedIndex = 0
    root.cursorActive = true
    root.moveOpen = false
    root.disarmPointer()
    root.rebuildDisplay()
  }

  function cycleView(delta) {
    var ids = root.navIds()
    var i = ids.indexOf(root.view)
    root.setView(ids[(i + delta + ids.length) % ids.length])
  }

  function jumpDigit(d) {
    var ids = root.navIds()
    if (d >= 1 && d <= ids.length) root.setView(ids[d - 1])
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildDisplay(true)
  }

  function toggleScope() {
    root.scopeAll = !root.scopeAll
    root.selectedIndex = 0
    root.rebuildDisplay()
  }

  function select(delta) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    resultList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function selectAbsolute(index) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    root.cursorActive = true
    root.selectedIndex = Math.max(0, Math.min(index, displayModel.count - 1))
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function disarmPointer() { pointerGate.reset() }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  // ---- confirm dialogs -------------------------------------------------
  function requestClearHistory() {
    if (root.history.length === 0) return
    root.confirmKind = "clear"
    clearConfirm.selectedIndex = 1
    root.confirmOpen = true
  }

  function requestDeleteGroup() {
    if (!root.groupById(root.view)) return
    root.confirmKind = "group"
    clearConfirm.selectedIndex = 1
    root.confirmOpen = true
  }

  function cancelConfirm() {
    root.confirmOpen = false
    root.disarmPointer()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function acceptConfirm() {
    if (root.confirmKind === "bulk") {
      root.confirmOpen = false
      root.bulkConfirmed = true
      root.deleteMarked()
      root.disarmPointer()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      return
    }
    if (root.confirmKind === "group") {
      root.deleteGroup(root.view)
    } else {
      root.history = ClipboardHistory.clearHistory()
      root.saveHistory()
      root.selectedIndex = 0
      root.cursorActive = false
      root.rebuildDisplay()
    }
    root.disarmPointer()
    root.confirmOpen = false
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // ---- entries ---------------------------------------------------------
  function removeDisplayIndex(index) {
    if (index < 0 || index >= displayModel.count) return

    var row = displayModel.get(index)
    if (row.pinned) {
      root.selectedIndex = index
      root.pinSelected()
      return
    } else {
      root.history = ClipboardHistory.removeEntryAt(root.history, row.historyIndex)
      root.saveHistory()
    }

    if (displayModel.count <= 1) {
      root.selectedIndex = 0
      root.cursorActive = false
    } else if (root.selectedIndex >= displayModel.count - 1) {
      root.selectedIndex = displayModel.count - 2
    }

    root.disarmPointer()
    root.rebuildDisplay()
  }

  function setTab(id) {
    if (["clip", "links", "shots"].indexOf(id) < 0 || id === root.tab) return
    root.tab = id
    root.moveOpen = false
    root.xformOpen = false
    root.selectedIndex = 0
    root.setCfg("tab", id)
    if (id === "shots") shotsTab.onOpened()
    else root.rebuildDisplay()
  }

  function cycleTab(d) {
    var order = ["clip", "links", "shots"]
    var i = order.indexOf(root.tab)
    root.setTab(order[(i + d + order.length) % order.length])
  }

  function refocus() { Qt.callLater(function() { keyCatcher.forceActiveFocus() }) }
  function queueChmod() { chmodTimer.restart() }

  // A toast whose Undo runs an arbitrary function (used by the Screenshots tab).
  function showActionToast(text, undoFn, ms) {
    toastTimer.interval = ms || 4500
    root.toastText = text
    root.toastUndoable = !!undoFn
    root.toastMovable = false
    root.toastSnapshot = null
    root.toastTomb = null
    root.toastUndoFn = undoFn
    toastTimer.restart()
  }

  function showToast(text, undoable, movable, snapshot) {
    root.toastUndoFn = null
    root.toastText = text
    root.toastUndoable = undoable
    root.toastMovable = movable
    root.toastSnapshot = snapshot
    root.toastTomb = null
    toastTimer.restart()
  }

  // Undo is a normal edit with a fresh timestamp, so a synced machine accepts it
  // instead of restoring the version that was just undone.
  function undoToast() {
    if (root.toastUndoFn) {
      var fn = root.toastUndoFn
      root.toastUndoFn = null
      fn()
      toastTimer.stop()
      root.toastText = ""
      return
    }
    if (root.toastSnapshot !== null) {
      var now = Date.now()
      var current = {}
      for (var i = 0; i < root.pins.length; i++) {
        var c = ClipboardHistory.normalizeEntry(root.pins[i])
        if (c) current[ClipboardHistory.entryKey(c)] = JSON.stringify(c)
      }
      var restored = []
      var kept = {}
      for (var j = 0; j < root.toastSnapshot.length; j++) {
        var n = ClipboardHistory.normalizeEntry(root.toastSnapshot[j])
        if (!n) continue
        var key = ClipboardHistory.entryKey(n)
        kept[key] = true
        if (current[key] !== JSON.stringify(n)) n.at = now
        restored.push(n)
      }
      var tomb = Object.assign({}, root.tombstones)
      for (var k in current) if (!kept[k]) tomb[ClipboardHistory.keyHash(k)] = now
      root.pins = restored
      root.tombstones = tomb
      root.savePins()
      root.saveCfg()
      root.rebuildDisplay()
    }
    toastTimer.stop()
    root.toastText = ""
  }

  function pinSelected() {
    var row = root.activeRow
    if (!row) return
    var snapshot = root.pins.slice()
    if (row.pinned) {
      var title = row.previewText
      var tsnap = root.tombstones
      root.removePinAt(row.pinIndex)
      root.savePins()
      root.saveCfg()
      root.rebuildDisplay()
      root.showToast("Unpinned " + (title.length > 28 ? title.slice(0, 28) + "…" : title), true, false, snapshot)
      root.toastTomb = tsnap
    } else {
      var entry = root.history[row.historyIndex]
      if (!entry) return
      root.pins = ClipboardHistory.addPin(root.pins, entry, root.lastGroup)
      root.moveKey = ClipboardHistory.entryKey(ClipboardHistory.normalizeEntry(entry))
      root.savePins()
      root.rebuildDisplay()
      root.showToast("Pinned to " + (root.lastGroup ? root.groupName(root.lastGroup) : "All pinned"), true, root.groups.length > 0, snapshot)
    }
  }

  function openMove() {
    var row = root.activeRow
    if (row && row.pinned) {
      var e = root.pins[row.pinIndex]
      if (e) root.moveKey = ClipboardHistory.entryKey(ClipboardHistory.normalizeEntry(e))
    }
    if (!root.moveKey) return
    root.moveOpen = true
  }

  function moveTo(gid) {
    var idx = ClipboardHistory.pinIndexByKey(root.pins, root.moveKey)
    root.moveOpen = false
    if (idx < 0) return
    var snapshot = root.pins.slice()
    root.pins = ClipboardHistory.setPinGroup(root.pins, idx, gid)
    if (gid) { root.lastGroup = gid; root.saveCfg() }
    root.savePins()
    root.rebuildDisplay()
    root.showToast(gid ? "Moved to " + root.groupName(gid) : "Removed from its group", true, false, snapshot)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function setLabel(pinIndex, text) {
    if (pinIndex < 0) return
    root.pins = ClipboardHistory.setPinLabel(root.pins, pinIndex, text)
    root.savePins()
    root.rebuildDisplay()
  }

  // ---- groups ----------------------------------------------------------
  function beginGroupEdit(mode) {
    if (mode === "rename" && !root.groupById(root.view)) return
    root.groupEditMode = mode
    root.groupEditOpen = true
    groupInput.text = mode === "rename" ? root.groupName(root.view) : ""
    Qt.callLater(function() { groupInput.forceActiveFocus(); groupInput.selectAll() })
  }

  function finishGroupEdit(commit) {
    var name = groupInput.text.trim()
    var mode = root.groupEditMode
    root.groupEditOpen = false
    if (commit && name) {
      if (mode === "rename") {
        var next = []
        for (var i = 0; i < root.groups.length; i++) {
          var g = root.groups[i]
          next.push(g.id === root.view ? { id: g.id, name: name, h: g.h, at: Date.now() } : g)
        }
        root.groups = next
        root.saveCfg()
        root.rebuildDisplay()
      } else {
        var id = name.toLowerCase().replace(/[^a-z0-9]+/g, "-") + "-" + Date.now().toString(36)
        root.groups = root.groups.concat([{ id: id, name: name, h: root.hues[root.groups.length % root.hues.length], at: Date.now() }])
        root.saveCfg()
        root.setView(id)
      }
    }
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function deleteGroup(id) {
    root.tombstones = ClipboardHistory.tombstoneFor(root.tombstones, "group:" + id, Date.now())
    root.pins = ClipboardHistory.ungroupPins(root.pins, id)
    root.savePins()
    var next = []
    for (var i = 0; i < root.groups.length; i++) if (root.groups[i].id !== id) next.push(root.groups[i])
    root.groups = next
    if (root.lastGroup === id) root.lastGroup = next.length > 0 ? next[0].id : ""
    root.saveCfg()
    root.view = "all"
    root.selectedIndex = 0
    root.rebuildDisplay()
  }

  // ---- usage and paste environment --------------------------------------
  function recordUse(key) {
    if (!key) return
    var m = Object.assign({}, root.meta)
    var hk = ClipboardHistory.keyHash(key)
    var e = m[hk] || { t: Date.now(), seen: false, app: "" }
    m[hk] = { t: e.t, seen: e.seen, app: e.app, n: (e.n || 0) + 1 }
    root.meta = m
    root.saveMetaSoon()
  }

  function pasteEnv() {
    return ["env", "CLIPBOARD_PASTE_MODE=" + (root.cfg.pasteMode || "shift-insert")]
  }

  // ---- raw entries -------------------------------------------------------
  function entryKeyOf(e) {
    var n = ClipboardHistory.normalizeEntry(e)
    return n ? ClipboardHistory.entryKey(n) : ""
  }

  function rawByKey(key) {
    for (var i = 0; i < root.pins.length; i++) {
      var p = ClipboardHistory.normalizeEntry(root.pins[i])
      if (p && ClipboardHistory.entryKey(p) === key) return p.type === "text" ? p.text : ""
    }
    for (var j = 0; j < root.history.length; j++) {
      var h = ClipboardHistory.normalizeEntry(root.history[j])
      if (h && ClipboardHistory.entryKey(h) === key) return h.type === "text" ? h.text : ""
    }
    return ""
  }

  function rawText(row) { return row ? root.rawByKey(row.key) : "" }

  // ---- when and where something was copied -------------------------------
  function ingestHistory() {
    if (!root.metaReady) return
    var keys = []
    for (var i = 0; i < root.stockHistory.length; i++) {
      var k = root.entryKeyOf(root.stockHistory[i])
      if (k) keys.push(k)
    }
    var fresh = []
    for (var j = 0; j < keys.length; j++) if (!root.meta[ClipboardHistory.keyHash(keys[j])]) fresh.push(keys[j])
    var top = keys.length > 0 ? keys[0] : ""
    var recopied = root.historySeen && top !== "" && top !== root.lastTopKey && !root.cfg.paused && !!root.meta[ClipboardHistory.keyHash(top)] && fresh.indexOf(top) < 0
    root.lastTopKey = top
    var first = !root.historySeen
    root.historySeen = true
    if (fresh.length === 0 && !recopied) { root.sweepAll(); return }

    // Private mode: anything copied while paused is dropped again right away.
    if (!first && root.cfg.paused && fresh.length > 0) {
      root.dropKeys(fresh)
      return
    }

    var now = Date.now()
    var m = Object.assign({}, root.meta)
    for (var f = 0; f < fresh.length; f++) m[ClipboardHistory.keyHash(fresh[f])] = { t: now, seen: first, app: "" }
    if (recopied) m[ClipboardHistory.keyHash(top)] = { t: now, seen: false, app: "", n: root.meta[ClipboardHistory.keyHash(top)].n || 0 }
    root.meta = m
    if (!first) {
      root.pendingAppKeys = fresh.concat(recopied ? [top] : [])
      appProc.running = true
    }
    root.saveMetaSoon()
    root.sweepAll()
  }

  function dropKeys(keys) {
    var gone = {}
    for (var i = 0; i < keys.length; i++) gone[keys[i]] = true
    var pinned = {}
    for (var p = 0; p < root.pins.length; p++) pinned[root.entryKeyOf(root.pins[p])] = true
    var keep = []
    var removed = 0
    for (var h = 0; h < root.history.length; h++) {
      var k = root.entryKeyOf(root.history[h])
      if (gone[k] && !pinned[k]) { removed++; continue }
      keep.push(root.history[h])
    }
    if (removed > 0) {
      root.history = keep
      root.saveHistory()
      if (root.opened) root.rebuildDisplay()
    }
  }

  function isExcludedApp(cls) {
    var list = root.cfg.excludeApps || []
    for (var i = 0; i < list.length; i++) if (cls.indexOf(String(list[i]).toLowerCase()) >= 0) return true
    return false
  }

  function assignApp(raw) {
    var cls = ""
    try {
      var j = JSON.parse(String(raw || "{}"))
      cls = String(j["class"] || j.initialClass || "")
    } catch (e) { cls = "" }
    if (cls.indexOf(".") >= 0) cls = cls.slice(cls.lastIndexOf(".") + 1)
    cls = cls.toLowerCase()
    if (!cls || root.pendingAppKeys.length === 0) return
    var m = Object.assign({}, root.meta)
    var drop = []
    for (var i = 0; i < root.pendingAppKeys.length; i++) {
      var key = root.pendingAppKeys[i]
      var hk = ClipboardHistory.keyHash(key)
      if (m[hk]) m[hk] = { t: m[hk].t, seen: m[hk].seen, app: cls, n: m[hk].n || 0 }
      if (root.isExcludedApp(cls)) drop.push(key)
    }
    root.meta = m
    root.pendingAppKeys = []
    if (drop.length > 0) root.dropKeys(drop)
    root.saveMetaSoon()
    if (root.opened) root.rebuildDisplay()
  }

  function loadMeta(raw) {
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      root.meta = parsed && typeof parsed === "object" && !Array.isArray(parsed) ? ClipboardHistory.migrateKeys(parsed) : {}
    } catch (e) { root.meta = {} }
    root.metaReady = true
    root.ingestHistory()
  }

  function saveMetaSoon() { metaSaveTimer.restart() }

  function saveMeta() {
    if (!root.historySeen) return
    var live = {}
    for (var i = 0; i < root.history.length; i++) live[ClipboardHistory.keyHash(root.entryKeyOf(root.history[i]))] = true
    for (var j = 0; j < root.pins.length; j++) live[ClipboardHistory.keyHash(root.entryKeyOf(root.pins[j]))] = true
    var out = {}
    for (var k in root.meta) if (live[k]) out[k] = root.meta[k]
    metaFile.setText(JSON.stringify(out) + "\n")
    chmodTimer.restart()
  }

  function sweepAll() {
    root.sweepSecrets()
    root.sweepRetention()
  }

  function sweepRetention() {
    var days = Number(root.cfg.keepDays) || 0
    var cap = Number(root.cfg.maxEntries) || 0
    if (!root.metaReady || !root.historySeen || (days <= 0 && cap <= 0)) return
    var pinned = {}
    for (var p = 0; p < root.pins.length; p++) pinned[root.entryKeyOf(root.pins[p])] = true
    var out = ClipboardHistory.trimHistory(root.history, root.meta, pinned, days, cap, Date.now())
    if (out.length !== root.history.length) {
      root.history = out
      root.saveHistory()
      if (root.opened) root.rebuildDisplay()
    }
  }

  // Credentials that were copied and never pinned are removed after a while.
  function sweepSecrets() {
    var ttl = Number(root.cfg.secretTtl) || 0
    if (ttl <= 0 || !root.metaReady || !root.historySeen || !root.cfgLoadedOnce || !root.cfgOk) return
    var pinned = {}
    for (var p = 0; p < root.pins.length; p++) pinned[root.entryKeyOf(root.pins[p])] = true
    var now = Date.now()
    var keep = []
    var removed = 0
    for (var i = 0; i < root.history.length; i++) {
      var n = ClipboardHistory.normalizeEntry(root.history[i])
      if (n && n.type === "text" && ClipboardHistory.secretIsSure(ClipboardHistory.secretKind(n.text))) {
        var key = ClipboardHistory.entryKey(n)
        var m = root.meta[ClipboardHistory.keyHash(key)]
        if (!pinned[key] && m && now - m.t > ttl * 60000) { removed++; continue }
      }
      keep.push(root.history[i])
    }
    if (removed > 0) {
      root.history = keep
      root.saveHistory()
      root.saveMetaSoon()
      if (root.opened) root.rebuildDisplay()
    }
  }

  // ---- paste queue -------------------------------------------------------
  function toggleMark(row) {
    if (!row) return
    var next = root.markedKeys.slice()
    var i = next.indexOf(row.key)
    if (i >= 0) next.splice(i, 1)
    else next.push(row.key)
    root.markedKeys = next
  }

  function addMark(key) {
    if (root.markedKeys.indexOf(key) < 0) root.markedKeys = root.markedKeys.concat([key])
  }

  // Shift+Up/Down: mark the current row and the one the cursor moves onto.
  function extendMark(delta) {
    if (displayModel.count === 0) return
    root.addMark(displayModel.get(root.selectedIndex).key)
    root.selectedIndex = Math.max(0, Math.min(displayModel.count - 1, root.selectedIndex + delta))
    root.addMark(displayModel.get(root.selectedIndex).key)
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  // Click in select mode: toggles one row, or marks a range with Shift.
  // Shift+click ticks everything between the anchor and the clicked row. The anchor is
  // the last row ticked, or, before anything is ticked, the highlighted row.
  function clickMark(index, shift) {
    var anchor = root.lastMarkIndex >= 0 ? root.lastMarkIndex : (root.markedKeys.length === 0 && shift ? root.selectedIndex : -1)
    root.cursorActive = true
    root.selectedIndex = index
    root.selectMode = true
    if (shift && anchor >= 0 && anchor < displayModel.count) {
      var lo = Math.min(anchor, index)
      var hi = Math.max(anchor, index)
      for (var i = lo; i <= hi; i++) root.addMark(displayModel.get(i).key)
    } else {
      root.toggleMark(displayModel.get(index))
    }
    root.lastMarkIndex = index
  }

  // Ctrl+A: everything the current view and search match, not just the rows on screen.
  function markAllShown() {
    var q = (root.tab === "links" ? "is:url " : "") + root.filterText
    var res = ClipboardHistory.queryIndex(root.currentIndex(), q, 100000, root.view, root.scopeAll, root.groupNameMap(), root.subTab)
    var keys = res.rows.map(function(r) { return r.key })
    var all = keys.length > 0 && keys.every(function(k) { return root.markedKeys.indexOf(k) >= 0 })
    if (all) {
      root.markedKeys = root.markedKeys.filter(function(k) { return keys.indexOf(k) < 0 })
    } else {
      var next = root.markedKeys.slice()
      for (var i = 0; i < keys.length; i++) if (next.indexOf(keys[i]) < 0) next.push(keys[i])
      root.markedKeys = next
    }
    // Show tick boxes while something is selected, so Delete's target is visible.
    root.selectMode = root.markedKeys.length > 0
    root.lastMarkIndex = -1
  }

  // Deletes every marked entry (pins and history). One Undo brings all of them back.
  function deleteMarked() {
    var keys = root.markedKeys.slice()
    if (keys.length === 0) return
    if (keys.length > 10 && !root.bulkConfirmed) {
      root.confirmKind = "bulk"
      clearConfirm.selectedIndex = 1
      root.confirmOpen = true
      return
    }
    root.bulkConfirmed = false
    var set = {}
    for (var i = 0; i < keys.length; i++) set[keys[i]] = true
    var pinsSnap = root.pins.slice()
    var tombSnap = root.tombstones
    var histSnap = root.history.slice()
    var stockSnap = root.stockHistory.slice()
    var now = Date.now()
    var tomb = Object.assign({}, root.tombstones)
    var nextPins = []
    for (var p = 0; p < root.pins.length; p++) {
      var pk = root.entryKeyOf(root.pins[p])
      if (set[pk]) tomb[ClipboardHistory.keyHash(pk)] = now
      else nextPins.push(root.pins[p])
    }
    var pinsRemoved = root.pins.length - nextPins.length
    var nextHist = root.history.filter(function(e) { return !set[root.entryKeyOf(e)] })
    var count = Math.max(keys.length, 0)
    if (pinsRemoved > 0) {
      root.pins = nextPins
      root.tombstones = tomb
      root.savePins()
      root.saveCfg()
    }
    root.history = nextHist
    root.saveHistory()
    root.markedKeys = []
    root.lastMarkIndex = -1
    if (displayModel.count <= 1) root.selectedIndex = 0
    root.rebuildDisplay()
    root.showActionToast(count + (count === 1 ? " entry deleted" : " entries deleted"), function() {
      var restored = []
      for (var r = 0; r < pinsSnap.length; r++) {
        var n = ClipboardHistory.normalizeEntry(pinsSnap[r])
        if (n && set[ClipboardHistory.entryKey(n)]) n.at = Date.now()
        if (n) restored.push(n)
      }
      root.pins = restored
      root.tombstones = tombSnap
      if (pinsRemoved > 0) { root.savePins(); root.saveCfg() }
      root.history = histSnap
      root.archive = histSnap
      root.writeArchive()
      if (root.historyOk) {
        root.stockHistory = stockSnap
        historyFile.setText(JSON.stringify(stockSnap, null, 2) + "\n")
      }
      root.rebuildDisplay()
    }, 10000)
  }

  // ---- clean up: selects groups of entries you probably don't need ----------
  function cleanupKeys(kind) {
    var pinned = {}
    for (var p = 0; p < root.pins.length; p++) pinned[root.entryKeyOf(root.pins[p])] = true
    var out = []
    var cutoff = Date.now() - 30 * 86400000
    for (var i = 0; i < root.history.length; i++) {
      var n = ClipboardHistory.normalizeEntry(root.history[i])
      if (!n) continue
      var key = ClipboardHistory.entryKey(n)
      if (pinned[key]) continue
      var m = root.meta[ClipboardHistory.keyHash(key)]
      if (kind === "old" && m && !m.n && m.t && m.t < cutoff) out.push(key)
      else if (kind === "secrets" && n.type === "text" && ClipboardHistory.secretKind(n.text)) out.push(key)
      else if (kind === "big" && n.type === "text" && n.text.length > 20000) out.push(key)
    }
    return out
  }

  function openCleanup() {
    root.cleanCounts = { old: root.cleanupKeys("old").length, secrets: root.cleanupKeys("secrets").length, big: root.cleanupKeys("big").length }
    root.cleanOpen = true
  }

  function applyCleanup(kind) {
    root.cleanOpen = false
    var keys = root.cleanupKeys(kind)
    if (keys.length === 0) { root.showToast("Nothing to clean up here", false, false, null); return }
    if (root.view !== "recent") root.setView("recent")
    root.markedKeys = keys
    root.showActionToast(keys.length + " selected. Press Delete to remove them, Esc to cancel.", null, 8000)
  }

  function pasteQueue(sep) {
    var texts = []
    for (var i = 0; i < root.markedKeys.length; i++) {
      var t = root.rawByKey(root.markedKeys[i])
      if (t) texts.push(t)
    }
    if (texts.length === 0) return
    // Each text travels as one command-line argument, which the kernel caps near 128 KB.
    for (var big = 0; big < texts.length; big++) {
      if (texts[big].length >= 40000) { root.showToast("One of the entries is too large to paste in a queue", false, false, null); return }
    }
    for (var u = 0; u < root.markedKeys.length; u++) root.recordUse(root.markedKeys[u])
    root.close()
    Quickshell.execDetached(root.pasteEnv().concat([root.pluginDir + "/paste-queue.sh", sep]).concat(texts))
  }

  // ---- transforms --------------------------------------------------------
  function openXform() {
    var row = root.activeRow
    if (!row || row.entryType === "image") return
    root.xformOpen = true
  }

  function applyXform(index) {
    var list = ClipboardHistory.transformList
    var row = root.activeRow
    root.xformOpen = false
    if (!row || index < 0 || index >= list.length) return
    var out = ClipboardHistory.applyTransform(list[index].id, root.rawText(row), { btoa: Qt.btoa, atob: Qt.atob })
    if (out === null) {
      root.showToast("Can't apply " + list[index].label + " to this text", false, false, null)
      return
    }
    root.recordUse(row.key)
    root.opened = false
    root.pasteLiteral(out, false)
  }

  // ---- quick edit (F4): the preview becomes a text box --------------------
  // A pin is rewritten in place and keeps its label, group, tags and star. A history
  // entry is never altered: its edit is copied, and the stock plugin then records the
  // copy as a new entry at the top.
  // List rebuilds (a new copy, a screenshot) empty and refill the list, so the editor can only
  // close when the user moves to another row, never on activeRow going null.
  onSelectedIndexChanged: if (root.editing && root.activeRow && root.activeRow.key !== root.editKey) root.editing = false

  function beginEdit() {
    var row = root.activeRow
    if (!row || row.entryType === "image") return
    if (root.previewMode === "off") { root.showToast("Make the window bigger (^=) to edit", false, false, null); return }
    if (row.secret !== "" && root.cfg.mask && !root.revealSecrets) { root.showToast("Press ^R to reveal this entry before editing", false, false, null); return }
    root.editKey = row.key
    root.editDiscardArmed = false
    root.editing = true
    editInput.text = root.rawText(row)
    Qt.callLater(function() { editInput.forceActiveFocus(); editInput.cursorPosition = editInput.length })
  }

  function cancelEdit() {
    root.editing = false
    root.refocus()
  }

  // Esc on an edit that changed the text asks once more before throwing the draft away.
  function escapeEdit() {
    if (editInput.text !== root.rawByKey(root.editKey) && !root.editDiscardArmed) {
      root.editDiscardArmed = true
      root.showToast("Unsaved edit. Press Esc again to discard it, or Ctrl+S to save", false, false, null)
      return
    }
    root.cancelEdit()
  }

  // mode: "save" (pin: rewrite it; history: copy the edit) or "paste" (paste the edit, change nothing stored).
  function finishEdit(mode) {
    var row = root.activeRow
    if (!root.editing || !row || row.key !== root.editKey) { root.cancelEdit(); return }
    var text = editInput.text
    if (text.trim() === "") { root.showToast("Can't use empty text", false, false, null); return }
    if (mode === "paste") {
      root.editing = false
      root.recordUse(row.key)
      root.opened = false
      root.pasteLiteral(text, false)
      return
    }
    if (text === root.rawByKey(root.editKey)) { root.cancelEdit(); return }
    if (!row.pinned) {
      // The edit is recorded only because the stock plugin sees the new copy, which private mode suppresses.
      if (root.cfg.paused) { root.showToast("Private mode is on, so this copy would not be kept. Turn it off (^⇧P) first", false, false, null); return }
      root.editing = false
      root.opened = false
      root.pasteLiteral(text, true)
      return
    }
    var idx = ClipboardHistory.pinIndexByKey(root.pins, root.editKey)
    if (!root.pinsOk) { root.showToast("The pins file could not be read, so nothing can be saved", false, false, null); return }
    if (idx < 0) { root.cancelEdit(); return }
    var newKey = ClipboardHistory.entryKey({ type: "text", text: text })
    if (ClipboardHistory.pinIndexByKey(root.pins, newKey) >= 0) { root.showToast("Another pin already has exactly this text", false, false, null); return }
    var snapshot = root.pins.slice()
    var tsnap = root.tombstones
    root.tombstones = ClipboardHistory.tombstoneFor(root.tombstones, root.editKey, Date.now())
    root.pins = ClipboardHistory.mapPin(root.pins, idx, function(e) { e.text = text })
    root.editing = false
    root.savePins()
    root.saveCfg()
    root.rebuildDisplay()
    for (var i = 0; i < displayModel.count; i++) {
      if (displayModel.get(i).key === newKey) { root.selectedIndex = i; break }
    }
    root.showToast("Pin updated", true, false, snapshot)
    root.toastTomb = tsnap
    root.refocus()
  }

  // ---- templates ({{date}}, {{clip}}, {{ask:Name}}) ---------------------
  function runTemplate(row, copyOnly) {
    var raw = root.rawText(row)
    var tok = ClipboardHistory.templateTokens(raw)
    root.askCopy = copyOnly
    root.askRaw = raw
    root.askVals = ({})
    if (tok.asks.length === 0) { root.finishTemplate(); return }
    root.askNames = tok.asks
    root.askIdx = 0
    root.askOpen = true
    askInput.text = ""
    Qt.callLater(function() { askInput.forceActiveFocus() })
  }

  function answerAsk() {
    var vals = Object.assign({}, root.askVals)
    vals[root.askNames[root.askIdx]] = askInput.text
    root.askVals = vals
    if (root.askIdx + 1 >= root.askNames.length) { root.finishTemplate(); return }
    root.askIdx = root.askIdx + 1
    askInput.text = ""
  }

  function cancelAsk() {
    root.askOpen = false
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function finishTemplate() {
    var clip = root.history.length > 0 ? String((ClipboardHistory.normalizeEntry(root.history[0]) || {}).text || "") : ""
    var out = ClipboardHistory.expandTemplate(root.askRaw, { now: new Date(), clip: clip, asks: root.askVals })
    root.askOpen = false
    root.opened = false
    root.pasteLiteral(out, root.askCopy)
  }

  // ---- pin the current clipboard without opening the overlay ------------
  function pinCurrentClipboard() {
    if (!root.pinsOk) return "blocked: the pins file is unreadable"
    if (root.history.length === 0) return "empty"
    var entry = ClipboardHistory.normalizeEntry(root.history[0])
    if (!entry) return "empty"
    root.pins = ClipboardHistory.addPin(root.pins, entry, root.lastGroup)
    root.savePins()
    var where = root.lastGroup ? root.groupName(root.lastGroup) : "All pinned"
    var secret = entry.type === "text" ? ClipboardHistory.secretKind(entry.text) : ""
    var preview = entry.type === "image" ? "Image" : secret ? "Hidden " + secret.toLowerCase() : entry.text.replace(/\s+/g, " ").slice(0, 40)
    Quickshell.execDetached(["notify-send", "-a", "Clipboard", "-t", "2500", "Pinned to " + where, preview])
    if (root.opened) root.rebuildDisplay()
    return "pinned"
  }

  // Long text goes through a file in the runtime dir; a single command-line argument is capped near
  // 128 KB, and the limit counts bytes (up to three per character), so the cutoff is conservative.
  function pasteLiteral(out, copyOnly) {
    if (out.length < 40000) {
      Quickshell.execDetached(root.pasteEnv().concat([root.pluginDir + "/paste-literal.sh"]).concat(copyOnly ? ["--copy-only"] : []).concat([out]))
      return
    }
    // The runtime dir is private to the user; a fixed name under /tmp would not be.
    var runtime = Quickshell.env("XDG_RUNTIME_DIR")
    if (!runtime) { root.showToast("Too large to paste (no private runtime folder)", false, false, null); return }
    root.bigPending = { out: out, copyOnly: copyOnly }
    bigFile.path = runtime + "/clipboard-pins-paste.txt"
    bigWriteTimer.restart()
  }

  function ocrSelected() {
    var row = root.activeRow
    if (!row || row.entryType !== "image" || !row.path) return
    root.opened = false
    Quickshell.execDetached([root.pluginDir + "/ocr.sh", row.path])
  }

  function togglePrivate() {
    root.setCfg("paused", !root.cfg.paused)
    Quickshell.execDetached(["notify-send", "-a", "Clipboard", "-t", "2500", root.cfg.paused ? "Private mode on" : "Private mode off", root.cfg.paused ? "New copies are not kept in history" : "Recording resumed"])
    return root.cfg.paused ? "on" : "off"
  }

  function openGroupByName(name) {
    var n = String(name || "").trim().toLowerCase()
    var id = ""
    if (n === "recent" || n === "all" || n === "frequent") id = n
    else for (var i = 0; i < root.groups.length; i++) if (root.groups[i].name.toLowerCase() === n) id = root.groups[i].id
    if (!id) return "unknown group"
    root.open("{}")
    root.view = id
    root.selectedIndex = 0
    root.saveCfg()
    root.rebuildDisplay()
    return "ok"
  }

  // ---- backup, import and folder sync -----------------------------------
  function expandHome(p) {
    var t = String(p || "").trim()
    return t.indexOf("~") === 0 ? Quickshell.env("HOME") + t.slice(1) : t
  }

  function currentState() { return { pins: root.pins, groups: root.groups, tombstones: root.tombstones } }

  function applyMerged(m) {
    if (ClipboardHistory.fingerprint(m) === ClipboardHistory.fingerprint(root.currentState())) return false
    root.pins = m.pins
    root.groups = m.groups
    root.tombstones = m.tombstones
    if (root.view !== "recent" && root.view !== "all" && root.view !== "frequent" && !root.groupById(root.view)) root.view = "all"
    root.savePins()
    root.saveCfg()
    if (root.opened) root.rebuildDisplay()
    return true
  }

  function queueSyncPush() {
    if (root.cfg.syncFolder) syncTimer.restart()
  }

  function syncFilePath() {
    return root.cfg.syncFolder ? root.expandHome(root.cfg.syncFolder) + "/clipboard-pins-sync.json" : ""
  }

  function writeSyncFile() {
    syncFile.setText(JSON.stringify(ClipboardHistory.makeSnapshot(root.pins, root.groups, root.tombstones, ""), null, 2) + "\n")
  }

  function handleSyncLoaded(raw) {
    if (!root.pinsReady || !root.cfgLoadedOnce) { syncTimer.restart(); return }
    var remote
    try { remote = JSON.parse(String(raw || "{}")) } catch (e) { root.statusMsg = "Sync file is not valid JSON"; return }
    if (Array.isArray(remote)) remote = { pins: remote }
    var merged = ClipboardHistory.mergeSnapshots(root.currentState(), remote, Date.now())
    var changed = root.applyMerged(merged)
    if (ClipboardHistory.fingerprint(merged) !== ClipboardHistory.fingerprint(remote)) root.writeSyncFile()
    root.statusMsg = changed ? "Synced: picked up changes from the sync folder" : "Sync folder is up to date"
  }

  function exportBackup() {
    var d = new Date()
    var pad = function(n) { return (n < 10 ? "0" : "") + n }
    var stamp = d.getFullYear() + pad(d.getMonth() + 1) + pad(d.getDate()) + "-" + pad(d.getHours()) + pad(d.getMinutes()) + pad(d.getSeconds())
    root.exportDir = root.stateDir + "/clipboard-backups"
    root.exportPending = root.exportDir + "/clipboard-pins-" + stamp + ".json"
    root.exportJson = JSON.stringify(ClipboardHistory.makeSnapshot(root.pins, root.groups, root.tombstones, ""), null, 2) + "\n"
    mkdirProc.running = true
  }

  function runImport() {
    var p = root.expandHome(root.cfg.importPath)
    if (!p) { root.statusMsg = "Type the path of a backup file first"; return }
    if (importFile.path === p) importFile.reload()
    else importFile.path = p
  }

  function handleImport(raw) {
    var data
    try { data = JSON.parse(String(raw || "")) } catch (e) { root.statusMsg = "That file is not valid JSON"; return }
    if (Array.isArray(data)) data = { pins: data }
    // An import only adds what is missing locally (and re-adds what was deleted); it never overwrites
    // or deletes what you already have.
    var stamp = Date.now()
    var newPins = []
    var inPins = data.pins || []
    for (var ip = 0; ip < inPins.length; ip++) {
      var cand = ClipboardHistory.normalizeEntry(inPins[ip])
      if (!cand || cand.type === "image") continue
      if (ClipboardHistory.pinIndexByKey(root.pins, ClipboardHistory.entryKey(cand)) >= 0) continue
      cand.at = stamp
      newPins.push(cand)
    }
    var newGroups = []
    var inGroups = data.groups || []
    for (var ig = 0; ig < inGroups.length; ig++) {
      if (inGroups[ig] && inGroups[ig].id && !root.groupById(inGroups[ig].id)) newGroups.push(Object.assign({}, inGroups[ig], { at: stamp }))
    }
    data = { pins: newPins, groups: newGroups, tombstones: {} }
    var before = root.pins.length
    var merged = ClipboardHistory.mergeSnapshots(root.currentState(), data, Date.now())
    root.applyMerged(merged)
    root.statusMsg = "Imported: " + Math.max(0, root.pins.length - before) + " new pins, " + root.groups.length + " groups"
  }

  function addExclude(name) {
    var n = String(name || "").trim().toLowerCase()
    var list = (root.cfg.excludeApps || []).slice()
    if (!n || list.indexOf(n) >= 0) return
    list.push(n)
    root.setCfg("excludeApps", list)
  }

  function removeExclude(name) {
    var list = (root.cfg.excludeApps || []).filter(function(x) { return x !== name })
    root.setCfg("excludeApps", list)
  }

  function runSync() {
    if (root.syncBusy) return
    root.syncBusy = true
    root.syncStatus = "Syncing…"
    syncProc.running = true
  }

  // ---- paste / copy / open --------------------------------------------
  // Pinned rows address the pins file; the rest address the stock history.
  function entryCommand(script, row, flags) {
    var path = row.pinned ? root.pinsPath : root.archivePath
    var index = row.pinned ? row.pinIndex : row.historyIndex
    var args = ["--history-index", String(index)]
    // Paste by key as well as by position, so a file that shifted since it was read pastes nothing
    // instead of a different entry.
    if (script === "paste-text.sh" && row.key.indexOf("text:") === 0) args = args.concat(["--expect", ClipboardHistory.keyHash(row.key)])
    return ["env", "CLIPBOARD_HISTORY_PATH=" + path, "CLIPBOARD_PASTE_MODE=" + (root.cfg.pasteMode || "shift-insert"), root.pluginDir + "/" + script].concat(flags).concat(args)
  }

  function activateIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    root.applySelected(displayModel.get(index))
  }

  function copyIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    root.copySelected(displayModel.get(index))
  }

  function openIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    root.openSelected(displayModel.get(index))
  }

  function applySelected(row) {
    if (!row) return
    root.recordUse(row.key)
    if (row.pinned && row.kind === "template") { root.runTemplate(row, false); return }
    root.opened = false
    if (row.entryType === "image") {
      Quickshell.execDetached(root.pasteEnv().concat([root.pluginDir + "/paste-file.sh", row.mime, row.path]))
    } else if (row.fullText) {
      Quickshell.execDetached(root.entryCommand("paste-text.sh", row, ["--shift-insert"]))
    }
  }

  function copySelected(row) {
    if (!row) return
    root.recordUse(row.key)
    if (row.pinned && row.kind === "template") { root.runTemplate(row, true); return }
    root.opened = false
    if (row.entryType === "image") {
      Quickshell.execDetached(root.pasteEnv().concat([root.pluginDir + "/paste-file.sh", "--copy-only", row.mime, row.path]))
    } else if (row.fullText) {
      Quickshell.execDetached(root.entryCommand("paste-text.sh", row, ["--copy-only"]))
    }
  }

  function openSelected(row) {
    if (!row) return
    root.opened = false
    Quickshell.execDetached(root.entryCommand("open.sh", row, []))
  }

  ListModel { id: displayModel }
  ListModel { id: navModel }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadHistory(text())
    onLoadFailed: root.loadHistory("[]", true)
    onFileChanged: reload()
  }

  FileView {
    id: archiveFile
    path: root.archivePath
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadArchive(text())
    onLoadFailed: root.loadArchive("[]", true)
  }

  FileView {
    id: pinsFile
    path: root.pinsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadPins(text())
    onLoadFailed: root.loadPins("[]", true)
    onFileChanged: reload()
  }

  FileView {
    id: cfgFile
    path: root.cfgPath
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadCfg(text())
    onLoadFailed: { root.cfgOk = true; root.seedGroups(); root.cfgLoadedOnce = true; root.saveCfg(); root.mergeArchive() }
  }

  Timer {
    id: toastTimer
    interval: 4500
    onTriggered: root.toastText = ""
  }

  FileView {
    id: metaFile
    path: root.stateDir + "/clipboard-meta.json"
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadMeta(text())
    onLoadFailed: root.loadMeta("{}")
  }

  Timer {
    id: metaSaveTimer
    interval: 800
    onTriggered: root.saveMeta()
  }

  FileView {
    id: bigFile
    path: ""
    atomicWrites: true
    printErrors: false
  }

  Timer {
    id: bigWriteTimer
    interval: 150
    onTriggered: { if (root.bigPending) { bigFile.setText(root.bigPending.out); bigRunTimer.restart() } }
  }

  Timer {
    id: bigRunTimer
    interval: 250
    onTriggered: {
      if (!root.bigPending) return
      Quickshell.execDetached(root.pasteEnv().concat([root.pluginDir + "/paste-literal.sh"]).concat(root.bigPending.copyOnly ? ["--copy-only"] : []).concat(["--file", bigFile.path]))
      root.bigPending = null
    }
  }

  Process {
    id: chmodProc
    command: ["bash", "-c", "d=\"$1\"; chmod 600 \"$d\"/clipboard-pins*.json* \"$d\"/clipboard-meta.json \"$d\"/clipboard-archive.json* \"$d\"/clipboard-shots.json* 2>/dev/null; [ -d \"$d/clipboard-backups\" ] && chmod 700 \"$d/clipboard-backups\" && chmod 600 \"$d\"/clipboard-backups/* 2>/dev/null; [ -d \"$d/clipboard-imports\" ] && chmod 700 \"$d/clipboard-imports\"; true", "_", root.stateDir]
  }

  Timer {
    id: chmodTimer
    interval: 1500
    onTriggered: chmodProc.running = true
  }

  Timer {
    interval: 4000
    running: true
    onTriggered: chmodProc.running = true
  }

  Timer {
    id: syncPollTimer
    interval: 300000
    repeat: true
    running: !!root.cfg.syncFolder
    onTriggered: syncFile.reload()
  }

  Timer {
    id: sweepTimer
    interval: 30000
    repeat: true
    running: true
    onTriggered: root.sweepAll()
  }

  Process {
    id: appProc
    command: ["hyprctl", "activewindow", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.assignApp(text)
    }
  }

  FileView {
    id: syncFile
    path: root.syncFilePath()
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.handleSyncLoaded(text())
    onLoadFailed: {
      if (!root.cfg.syncFolder) return
      if (!root.pinsReady || !root.cfgLoadedOnce) { syncTimer.restart(); return }
      root.writeSyncFile()
      root.statusMsg = "Created the sync file"
    }
    onFileChanged: reload()
  }

  Timer {
    id: syncTimer
    interval: 1500
    onTriggered: syncFile.reload()
  }

  FileView {
    id: importFile
    path: ""
    printErrors: false
    onLoaded: root.handleImport(text())
    onLoadFailed: root.statusMsg = "Could not read that file"
  }

  FileView {
    id: exportFile
    path: ""
    atomicWrites: true
    printErrors: false
  }

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", root.exportDir]
    onExited: { exportFile.path = root.exportPending; exportWriteTimer.restart() }
  }

  Timer {
    id: exportWriteTimer
    interval: 200
    onTriggered: { exportFile.setText(root.exportJson); root.statusMsg = "Exported to " + root.exportPending; chmodTimer.restart() }
  }

  Process {
    id: syncProc
    command: ["env", "CLIPBOARD_SYNC_PEER=" + (root.cfg.syncPeer || ""), root.pluginDir + "/sync.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.syncStatus = text.trim() || "Sync finished"
    }
    onExited: {
      root.syncBusy = false
      pinsFile.reload()
      cfgFile.reload()
    }
  }

  IpcHandler {
    target: "io.github.moeymakes.pinly"
    function pinCurrent(): string { return root.pinCurrentClipboard() }
    function togglePrivate(): string { return root.togglePrivate() }
    function openShots(): string { root.open("{}"); root.setTab("shots"); return "ok" }
    function triage(): string { root.open("{}"); root.setTab("shots"); shotsTab.triage = true; shotsTab.skip = 0; return "ok" }
    function exportBackup(): string { root.exportBackup(); return "exporting" }
    function importFile(path: string): string { root.setCfg("importPath", path); root.runImport(); return "importing" }
    function openGroup(name: string): string { return root.openGroupByName(name) }
    function sync(): string { root.runSync(); return "started" }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-pinly"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    Rectangle {
      x: card.x - root.sp(10)
      y: card.y - root.sp(4)
      width: card.width + root.sp(20)
      height: card.height + root.sp(22)
      radius: card.radius + root.sp(10)
      color: "#000000"
      opacity: 0.16
    }
    Rectangle {
      x: card.x - root.sp(4)
      y: card.y
      width: card.width + root.sp(8)
      height: card.height + root.sp(8)
      radius: card.radius + root.sp(4)
      color: "#000000"
      opacity: 0.2
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius + root.sp(4)
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: 0

      MouseArea { anchors.fill: parent; onClicked: { root.moveOpen = false } }

      // All keys land here unless a TextInput (new group, rename, label) owns focus.
      Item {
        id: keyCatcher
        anchors.fill: parent
        z: root.confirmOpen ? 20 : 0
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
          var alt = (event.modifiers & Qt.AltModifier) !== 0
          var shift = (event.modifiers & Qt.ShiftModifier) !== 0

          if (root.confirmOpen) {
            if (clearConfirm.handleKey(event)) event.accepted = true
            return
          }

          if (root.editing) {
            if (event.key === Qt.Key_Escape) root.escapeEdit()
            else editInput.forceActiveFocus()
            event.accepted = true
            return
          }

          if (event.key === Qt.Key_F1 || (ctrl && (event.key === Qt.Key_Slash || event.key === Qt.Key_Question))) {
            root.helpOpen = !root.helpOpen
            event.accepted = true
            return
          }
          if (root.helpOpen) {
            helpPanel.handleKey(event)
            event.accepted = true
            return
          }

          if (ctrl && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
            root.cycleTab(event.key === Qt.Key_Right ? 1 : -1)
            event.accepted = true
            return
          }

          if (root.tab === "shots") {
            if (ctrl && event.key === Qt.Key_Comma) { root.settingsOpen = !root.settingsOpen; event.accepted = true; return }
            if (ctrl && (event.key === Qt.Key_Equal || event.key === Qt.Key_Plus)) { root.cycleMode(1); event.accepted = true; return }
            if (ctrl && event.key === Qt.Key_Minus) { root.cycleMode(-1); event.accepted = true; return }
            if (event.key === Qt.Key_Escape && root.settingsOpen) { root.settingsOpen = false; event.accepted = true; return }
            if (root.settingsOpen) { event.accepted = true; return }
            if (shotsTab.handleKey(event)) event.accepted = true
            return
          }

          if (root.cleanOpen) {
            if (event.key === Qt.Key_Escape) { root.cleanOpen = false; event.accepted = true }
            else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_3) {
              root.applyCleanup(["old", "secrets", "big"][event.key - Qt.Key_1])
              event.accepted = true
            }
            return
          }

          if (root.xformOpen) {
            if (event.key === Qt.Key_Escape) { root.xformOpen = false; event.accepted = true }
            else if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
              var xd = event.key - Qt.Key_0
              root.applyXform(xd === 0 ? 9 : xd - 1)
              event.accepted = true
            }
            return
          }

          if (root.moveOpen) {
            if (event.key === Qt.Key_Escape) { root.moveOpen = false; event.accepted = true }
            else if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
              var d = event.key - Qt.Key_0
              if (d === 0) root.moveTo("")
              else if (d <= root.groups.length) root.moveTo(root.groups[d - 1].id)
              event.accepted = true
            } else if (event.key === Qt.Key_N && ctrl) {
              root.moveOpen = false
              root.beginGroupEdit("new")
              event.accepted = true
            }
            return
          }

          if (event.key === Qt.Key_Escape) {
            if (root.settingsOpen) root.settingsOpen = false
            else if (root.filterText) root.setFilter("")
            else if (root.markedKeys.length > 0) root.markedKeys = []
            else if (root.selectMode) root.selectMode = false
            else root.close()
            event.accepted = true
          } else if (ctrl && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.markedKeys.length > 0) {
            root.pasteQueue(shift ? "newline" : "tab")
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_A) {
            root.markAllShown()
            event.accepted = true
          } else if (ctrl && shift && event.key === Qt.Key_E) {
            if (root.activeRow && root.activeRow.pinned && root.previewMode !== "off") tagInput.forceActiveFocus()
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_D) {
            root.toggleFav()
            event.accepted = true
          } else if (alt && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
            root.cycleSubTab(event.key === Qt.Key_Right ? 1 : -1)
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_K) {
            root.openCleanup()
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_Space) {
            root.toggleMark(root.activeRow)
            if (root.selectedIndex < displayModel.count - 1) root.select(1)
            event.accepted = true
          } else if (ctrl && shift && event.key === Qt.Key_P) {
            root.togglePrivate()
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_O) {
            root.ocrSelected()
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_T) {
            root.openXform()
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_R) {
            root.revealSecrets = !root.revealSecrets
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_P) {
            root.pinSelected()
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_M) {
            root.openMove()
            event.accepted = true
          } else if (ctrl && (event.key === Qt.Key_Equal || event.key === Qt.Key_Plus)) {
            root.cycleMode(1)
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_Minus) {
            root.cycleMode(-1)
            event.accepted = true
          } else if (ctrl && shift && event.key === Qt.Key_Down) {
            root.nudgeDensity(-10)
            event.accepted = true
          } else if (ctrl && shift && event.key === Qt.Key_Up) {
            root.nudgeDensity(10)
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_Comma) {
            root.settingsOpen = !root.settingsOpen
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_N) {
            root.beginGroupEdit("new")
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_F) {
            root.toggleScope()
            event.accepted = true
          } else if (ctrl && !shift && event.key === Qt.Key_E) {
            if (root.activeRow && root.activeRow.pinned && root.previewMode !== "off") labelInput.forceActiveFocus()
            event.accepted = true
          } else if (event.key === Qt.Key_F2) {
            root.beginGroupEdit("rename")
            event.accepted = true
          } else if (event.key === Qt.Key_F4) {
            root.beginEdit()
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_Z) {
            if (root.toastText) root.undoToast()
            event.accepted = true
          } else if (ctrl && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
            root.jumpDigit(event.key - Qt.Key_0)
            event.accepted = true
          } else if (alt && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
            root.activateIndex(event.key - Qt.Key_1)
            event.accepted = true
          } else if (event.key === Qt.Key_Tab) {
            root.cycleView(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Backtab) {
            root.cycleView(-1)
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Delete) {
            if (root.markedKeys.length > 0 && !ctrl && !shift) root.deleteMarked()
            else if (ctrl) root.requestDeleteGroup()
            else if (shift) root.requestClearHistory()
            else root.removeDisplayIndex(root.selectedIndex)
            event.accepted = true
          } else if (shift && event.key === Qt.Key_Up) {
            root.extendMark(-1)
            event.accepted = true
          } else if (shift && event.key === Qt.Key_Down) {
            root.extendMark(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(6)
            event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            root.selectAbsolute(0)
            event.accepted = true
          } else if (event.key === Qt.Key_End) {
            root.selectAbsolute(displayModel.count - 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.cursorActive && alt) root.openIndex(root.selectedIndex)
            else if (root.cursorActive && shift) root.copyIndex(root.selectedIndex)
            else if (root.cursorActive) root.activateIndex(root.selectedIndex)
            else if (displayModel.count > 0) root.cursorActive = true
            event.accepted = true
          } else if (!ctrl && !alt && event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        ConfirmDialog {
          id: clearConfirm

          anchors.fill: parent
          opened: root.confirmOpen
          z: 10
          message: root.confirmKind === "bulk"
            ? "Delete " + root.markedKeys.length + " selected entries? You can undo for a few seconds afterwards."
            : root.confirmKind === "group"
            ? "Delete group “" + root.groupName(root.view) + "”? Its pins stay pinned, without a group."
            : "Delete clipboard history? Pinned items are kept."
          confirmText: "Delete"
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.cancelConfirm()
          onConfirmed: root.acceptConfirm()
        }
      }

      // ---- header ------------------------------------------------------
      Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.sp(40) + root.contentMargin * 2

        Row {
          id: tabStrip
          anchors.left: parent.left
          anchors.leftMargin: root.contentMargin
          anchors.verticalCenter: parent.verticalCenter
          spacing: root.sp(4)
          Repeater {
            model: [{ id: "clip", label: "Clipboard", cp: 0xF014C }, { id: "links", label: "Links", cp: 0xF0339 }, { id: "shots", label: "Screenshots", cp: 0xF02E9 }]
            delegate: Rectangle {
              required property var modelData
              readonly property bool on: root.tab === modelData.id
              height: root.sp(34)
              width: tabRow.implicitWidth + root.sp(22)
              radius: height / 2
              color: on ? root.foreground : (tabMouse.containsMouse ? root.selectedBackground : "transparent")
              Row {
                id: tabRow
                anchors.centerIn: parent
                spacing: root.sp(6)
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.glyph(modelData.cp)
                  color: parent.parent.on ? root.background : root.muted
                  font.family: root.fontFamily
                  font.pixelSize: root.fs(Style.font.title)
                }
                Text {
                  visible: !root.compactMode
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.label
                  color: parent.parent.on ? root.background : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: root.fs(Style.font.title)
                }
                Rectangle {
                  visible: modelData.id === "shots" && root.inboxCount > 0
                  anchors.verticalCenter: parent.verticalCenter
                  height: root.sp(18)
                  width: Math.max(height, inboxText.implicitWidth + root.sp(10))
                  radius: height / 2
                  color: root.accent
                  Text {
                    id: inboxText
                    anchors.centerIn: parent
                    text: root.inboxCount
                    color: root.accentText
                    font.family: root.fontFamily
                    font.pixelSize: root.fs(Style.font.caption)
                    font.bold: true
                  }
                }
              }
              MouseArea {
                id: tabMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setTab(modelData.id)
              }
            }
          }
        }

        Rectangle {
          id: searchPill
          anchors.left: tabStrip.right
          anchors.leftMargin: root.sp(10)
          anchors.right: selectBtn.left
          anchors.rightMargin: root.sp(10)
          anchors.verticalCenter: parent.verticalCenter
          height: root.sp(42)
          radius: root.cornerRadius
          color: root.surface

          Text {
            id: searchGlyph
            anchors.left: parent.left
            anchors.leftMargin: root.sp(14)
            anchors.verticalCenter: parent.verticalCenter
            text: root.glyph(0xF0349)
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.heading)
          }
          Text {
            id: searchText
            textFormat: Text.PlainText
            anchors.left: searchGlyph.right
            anchors.leftMargin: root.sp(10)
            anchors.right: privChip.visible ? privChip.left : scopeChip.left
            anchors.rightMargin: root.sp(10)
            anchors.verticalCenter: parent.verticalCenter
            text: root.tab === "shots" ? (shotsTab.query !== "" ? shotsTab.query : (shotsTab.searching ? "" : "Press / to search screenshots")) : (root.filterText || (root.compactMode ? "Search clipboard" : "Search clipboard   is: app: in:"))
            color: root.foreground
            opacity: (root.tab === "shots" ? shotsTab.query !== "" : root.filterText !== "") ? 1 : 0.5
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.heading)
            elide: Text.ElideRight
          }
          Rectangle {
            id: privChip
            visible: root.cfg.paused
            anchors.right: scopeChip.left
            anchors.rightMargin: root.sp(6)
            anchors.verticalCenter: parent.verticalCenter
            height: root.sp(26)
            width: privText.implicitWidth + root.sp(20)
            radius: height / 2
            color: root.accent
            Text {
              id: privText
              anchors.centerIn: parent
              text: "● Private"
              color: root.accentText
              font.family: root.fontFamily
              font.pixelSize: root.fs(Style.font.caption)
              font.bold: true
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.togglePrivate() }
          }

          Rectangle {
            id: scopeChip
            visible: root.tab !== "shots"
            anchors.right: parent.right
            anchors.rightMargin: root.sp(8)
            anchors.verticalCenter: parent.verticalCenter
            height: root.sp(26)
            width: scopeText.implicitWidth + root.sp(20)
            radius: height / 2
            color: scopeMouse.containsMouse ? root.selectedBackground : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07)
            Text {
              id: scopeText
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: root.scopeAll ? "Everywhere" : "in " + root.groupName(root.view)
              color: root.scopeAll ? root.accent : root.muted
              font.family: root.fontFamily
              font.pixelSize: root.fs(Style.font.caption)
            }
            MouseArea {
              id: scopeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleScope()
            }
          }
        }

        Rectangle {
          id: selectBtn
          visible: root.tab !== "shots"
          anchors.right: modeSeg.left
          anchors.rightMargin: visible ? root.sp(8) : 0
          anchors.verticalCenter: parent.verticalCenter
          width: visible ? root.sp(34) : 0
          height: root.sp(34)
          radius: width / 2
          color: root.selectMode || root.markedKeys.length > 0 ? root.accent : (selectMouse.containsMouse ? root.selectedBackground : root.surface)
          Text {
            anchors.centerIn: parent
            text: "☑"
            color: root.selectMode || root.markedKeys.length > 0 ? root.accentText : root.muted
            font.pixelSize: root.fs(Style.font.heading)
          }
          MouseArea {
            id: selectMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.selectMode = !root.selectMode; if (!root.selectMode) root.markedKeys = [] }
          }
        }

        Rectangle {
          id: modeSeg
          anchors.right: helpBtn.left
          anchors.rightMargin: root.sp(8)
          anchors.verticalCenter: parent.verticalCenter
          height: root.sp(34)
          width: root.sp(3 * 32 + 6)
          radius: height / 2
          color: root.surface
          Row {
            anchors.centerIn: parent
            spacing: 0
            Repeater {
              model: [{ m: "compact", t: "S" }, { m: "normal", t: "M" }, { m: "full", t: "L" }]
              delegate: Rectangle {
                required property var modelData
                readonly property bool chosen: root.cfg.mode === modelData.m
                width: root.sp(32)
                height: root.sp(28)
                radius: height / 2
                color: chosen ? root.accent : (segMouse.containsMouse ? root.selectedBackground : "transparent")
                Text {
                  anchors.centerIn: parent
                  text: modelData.t
                  color: chosen ? root.accentText : root.muted
                  font.family: root.fontFamily
                  font.pixelSize: root.fs(Style.font.caption)
                  font.bold: true
                }
                MouseArea {
                  id: segMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.setMode(modelData.m)
                }
              }
            }
          }
        }

        Rectangle {
          id: helpBtn
          anchors.right: gearBtn.left
          anchors.rightMargin: root.sp(6)
          anchors.verticalCenter: parent.verticalCenter
          width: root.sp(34)
          height: width
          radius: width / 2
          color: root.helpOpen ? root.accent : (helpMouse.containsMouse ? root.selectedBackground : root.surface)
          Text {
            anchors.centerIn: parent
            text: "?"
            color: root.helpOpen ? root.accentText : root.muted
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.title)
            font.bold: true
          }
          MouseArea {
            id: helpMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.helpOpen = !root.helpOpen
          }
        }

        Rectangle {
          id: gearBtn
          anchors.right: parent.right
          anchors.rightMargin: root.contentMargin
          anchors.verticalCenter: parent.verticalCenter
          width: root.sp(34)
          height: width
          radius: width / 2
          color: root.settingsOpen ? root.accent : (gearMouse.containsMouse ? root.selectedBackground : root.surface)
          Text {
            anchors.centerIn: parent
            text: root.glyph(0xF0493)
            color: root.settingsOpen ? root.accentText : root.muted
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.heading)
          }
          MouseArea {
            id: gearMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.settingsOpen = !root.settingsOpen
          }
        }
      }

      // ---- footer hints ------------------------------------------------
      Item {
        id: footer
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.sp(40)

        Row {
          anchors.left: parent.left
          anchors.leftMargin: root.contentMargin + root.sp(4)
          anchors.right: parent.right
          anchors.rightMargin: root.contentMargin
          anchors.verticalCenter: parent.verticalCenter
          spacing: root.sp(14)
          clip: true

          Repeater {
            model: root.tab === "shots"
              ? (root.compactMode
                ? [{ k: "F1", l: "help", a: "help" }, { k: "↵", l: "copy", a: "shotPaste" }, { k: "F", l: "fav", a: "shotFav" }, { k: "Del", l: "trash", a: "shotTrash" }, { k: "T", l: "triage", a: "shotTriage" }]
                : [{ k: "F1", l: "help", a: "help" }, { k: "↵", l: "copy image", a: "shotPaste" }, { k: "1-9", l: "category", a: "" }, { k: "F", l: "favorite", a: "shotFav" }, { k: "Del", l: "trash", a: "shotTrash" }, { k: "T", l: "triage", a: "shotTriage" }, { k: "/", l: "search", a: "shotSearch" }, { k: "Z", l: "undo", a: "shotUndo" }, { k: "^←→", l: "tab", a: "tab" }])
              : root.compactMode
              ? [{ k: "F1", l: "help", a: "help" }, { k: "↵", l: "paste", a: "paste" }, { k: "^P", l: "pin", a: "pin" }, { k: "⇥", l: "group", a: "group" }, { k: "^+", l: "size", a: "size" }]
              : [{ k: "F1", l: "help", a: "help" }, { k: "↵", l: "paste", a: "paste" }, { k: "⇧↵", l: "copy", a: "copy" }, { k: "^P", l: "pin", a: "pin" }, { k: "^M", l: "move", a: "move" }, { k: "^D", l: "favorite", a: "fav" }, { k: "^T", l: "transform", a: "transform" }, { k: "^K", l: "clean up", a: "cleanup" }, { k: "^␣", l: "select", a: "select" }, { k: "^R", l: "reveal", a: "reveal" }, { k: "⇥", l: "group", a: "group" }, { k: "⌥1-9", l: "quick", a: "" }, { k: "^,", l: "settings", a: "settings" }]
            // An Item wraps the Row so the click area can fill it without being laid
            // out by it (a MouseArea inside the Row, sized to the Row, is a polish loop
            // that stops every other Row in the window from laying out).
            delegate: Item {
              id: hint
              required property var modelData
              width: hintRow.implicitWidth
              height: hintRow.implicitHeight
              readonly property bool hot: modelData.a !== "" && hintMouse.containsMouse
              Row {
              id: hintRow
              anchors.verticalCenter: parent.verticalCenter
              spacing: root.sp(6)
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                height: root.sp(20)
                width: keyText.implicitWidth + root.sp(12)
                radius: root.sp(6)
                color: hint.hot ? root.selectedBackground : "transparent"
                border.width: 1
                border.color: root.line
                Text {
                  id: keyText
                  anchors.centerIn: parent
                  text: modelData.k
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: root.fs(Style.font.caption)
                }
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.l
                color: hint.hot ? root.foreground : root.muted
                opacity: hint.hot ? 1 : 0.85
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.caption)
              }
              }
              MouseArea {
                id: hintMouse
                anchors.fill: parent
                anchors.topMargin: -root.sp(6)
                anchors.bottomMargin: -root.sp(6)
                enabled: modelData.a !== ""
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.footerAction(modelData.a)
              }
            }
          }
        }
      }

      // ---- body: rail | list | preview --------------------------------
      Item {
        id: body
        visible: root.tab !== "shots"
        anchors.top: header.bottom
        anchors.bottom: footer.top
        anchors.bottomMargin: root.markedKeys.length > 0 ? root.sp(40) : 0
        anchors.left: parent.left
        anchors.right: parent.right

        // Rail
        Rectangle {
          id: rail
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          width: root.railWidth
          visible: !root.compactMode
          color: "transparent"

          ListView {
            id: navList
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: newGroupArea.top
            anchors.margins: root.sp(8)
            anchors.rightMargin: root.sp(9)
            model: navModel
            clip: true
            spacing: root.sp(2)
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              id: navRow
              required property int index
              required property string kind
              required property string gid
              required property string name
              required property int h
              required property int count
              required property int digit

              readonly property bool isSep: kind === "sep"
              readonly property bool current: !isSep && gid === root.view

              width: ListView.view.width
              height: isSep ? root.sp(26) : root.sp(36)
              radius: root.innerRadius + root.sp(2)
              color: current ? root.selectedBackground : (navMouse.containsMouse && !isSep ? Qt.rgba(root.selectedBackground.r, root.selectedBackground.g, root.selectedBackground.b, 0.55) : "transparent")

              Text {
                visible: navRow.isSep
                anchors.left: parent.left
                anchors.leftMargin: root.sp(8)
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.sp(3)
                text: "Groups"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.caption)
              }

              Row {
                visible: !navRow.isSep
                anchors.fill: parent
                anchors.leftMargin: root.sp(8)
                anchors.rightMargin: root.sp(8)
                spacing: root.sp(8)

                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: root.sp(20)
                  height: root.sp(20)
                  radius: Math.max(2, Math.round(root.innerRadius * 0.7))
                  color: navRow.kind === "group" ? root.badgeBg(navRow.h) : "transparent"
                  Text {
                    anchors.centerIn: parent
                    text: navRow.kind === "recent" ? root.glyph(0xF0150) : navRow.kind === "all" ? root.glyph(0xF0328) : navRow.kind === "frequent" ? "★" : navRow.name.charAt(0).toUpperCase()
                    color: navRow.kind === "group" ? root.badgeFg(navRow.h) : root.muted
                    font.family: root.fontFamily
                    font.pixelSize: navRow.kind === "group" ? root.fs(Style.font.caption) : root.fs(Style.font.title)
                    font.bold: navRow.kind === "group"
                  }
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.max(0, parent.width - root.sp(20) - countText.implicitWidth - (navRow.digit > 0 ? digitText.implicitWidth : 0) - parent.spacing * 3)
                  textFormat: Text.PlainText
                  text: navRow.name
                  color: navRow.current ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: root.fs(Style.font.title)
                  elide: Text.ElideRight
                }
                Text {
                  id: countText
                  anchors.verticalCenter: parent.verticalCenter
                  text: navRow.count
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: root.fs(Style.font.caption)
                }
                Text {
                  id: digitText
                  visible: navRow.digit > 0
                  anchors.verticalCenter: parent.verticalCenter
                  text: "^" + navRow.digit
                  color: root.muted
                  opacity: 0.8
                  font.family: root.fontFamily
                  font.pixelSize: root.fs(Style.font.caption)
                }
              }

              MouseArea {
                id: navMouse
                anchors.fill: parent
                enabled: !navRow.isSep
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setView(navRow.gid)
              }
            }
          }

          Item {
            id: newGroupArea
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: root.sp(8)
            anchors.rightMargin: root.sp(9)
            height: root.sp(38)

            Rectangle {
              anchors.fill: parent
              radius: root.innerRadius
              color: newGroupMouse.containsMouse ? root.selectedBackground : "transparent"
              border.width: 1
              border.color: root.line
              Row {
                anchors.centerIn: parent
                spacing: root.sp(8)
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.glyph(0xF0415)
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: root.fs(Style.font.title)
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "New group"
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: root.fs(Style.font.title)
                }
              }
              MouseArea {
                id: newGroupMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.beginGroupEdit("new")
              }
            }
          }
        }

        // Compact: groups become a chip strip above the list
        ListView {
          id: chipList
          visible: root.compactMode
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: root.contentMargin
          anchors.rightMargin: root.contentMargin
          height: root.sp(40)
          orientation: ListView.Horizontal
          model: navModel
          spacing: root.sp(6)
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          delegate: Rectangle {
            id: chip
            required property int index
            required property string kind
            required property string gid
            required property string name
            required property int h
            required property int count
            required property int digit
            readonly property bool current: gid === root.view
            visible: kind !== "sep"
            width: visible ? chipRow.implicitWidth + root.sp(22) : 0
            height: root.sp(32)
            radius: height / 2
            color: current ? root.accent : (chipMouse.containsMouse ? root.selectedBackground : root.surface)
            Row {
              id: chipRow
              anchors.centerIn: parent
              spacing: root.sp(6)
              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: chip.kind !== "group"
                text: chip.kind === "recent" ? root.glyph(0xF0150) : chip.kind === "frequent" ? "★" : root.glyph(0xF0328)
                color: chip.current ? root.accentText : root.muted
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.caption)
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.name
                textFormat: Text.PlainText
                color: chip.current ? root.accentText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.title)
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.count
                color: chip.current ? root.accentText : root.muted
                opacity: 0.8
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.caption)
              }
            }
            MouseArea {
              id: chipMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.setView(chip.gid)
            }
          }

          footer: Item {
            width: root.sp(38)
            height: root.sp(32)
            Rectangle {
              anchors.left: parent.left
              anchors.leftMargin: root.sp(6)
              width: root.sp(32)
              height: width
              radius: width / 2
              color: addMouse.containsMouse ? root.selectedBackground : "transparent"
              border.width: 1
              border.color: root.line
              Text { anchors.centerIn: parent; text: root.glyph(0xF0415); color: root.muted; font.family: root.fontFamily; font.pixelSize: root.fs(Style.font.title) }
              MouseArea { id: addMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.beginGroupEdit("new") }
            }
          }
        }

        // List
        Item {
          id: listArea
          x: root.railW
          y: root.topInset
          width: root.previewMode === "right" ? Math.round((body.width - root.railW) * (root.cfg.mode === "full" ? 0.44 : 0.55)) : body.width - root.railW
          height: root.previewMode === "bottom" ? body.height - root.topInset - root.sp(200) : body.height - root.topInset
          clip: true

          ListView {
            id: subStrip
            visible: root.view === "all"
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: root.sp(8)
            anchors.leftMargin: root.sp(10)
            anchors.rightMargin: root.sp(6)
            height: visible ? root.sp(32) : 0
            orientation: ListView.Horizontal
            spacing: root.sp(6)
            clip: true
            model: root.subTabs
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
              required property var modelData
              readonly property bool on: root.subTab === modelData.id
              width: subLabel.implicitWidth + root.sp(22)
              height: root.sp(28)
              radius: height / 2
              color: on ? root.accent : (subMouse.containsMouse ? root.selectedBackground : root.surface)
              Text {
                id: subLabel
                anchors.centerIn: parent
                text: modelData.label + "  " + modelData.count
                color: parent.on ? root.accentText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.caption)
              }
              MouseArea {
                id: subMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setSubTab(modelData.id)
              }
            }
          }

          ListView {
            id: resultList
            anchors.top: subStrip.visible ? subStrip.bottom : parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: root.sp(10)
            anchors.rightMargin: root.sp(6)
            anchors.topMargin: subStrip.visible ? root.sp(6) : root.sp(10)
            model: displayModel
            clip: true
            spacing: root.sp(2)
            boundsBehavior: Flickable.StopAtBounds

            footer: Item {
              width: ListView.view.width
              height: root.elsewhereCount > 0 ? root.sp(40) : 0
              visible: root.elsewhereCount > 0
              Text {
                anchors.left: parent.left
                anchors.leftMargin: root.sp(10)
                anchors.verticalCenter: parent.verticalCenter
                text: root.elsewhereCount + " more in other groups — click or ^F to search everywhere"
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.caption)
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.toggleScope()
                }
              }
            }

            delegate: Rectangle {
              id: row
              required property int index
              required property string entryType
              required property string previewText
              required property string subtitle
              required property string fullText
              required property string previewImage
              required property string kind
              required property string swatch
              required property string group
              required property bool pinned
              required property string key
              required property string app
              required property real ts
              required property bool seen
              required property string secret
              required property bool fav
              required property string tagsText

              readonly property bool masked: secret !== "" && root.cfg.mask && !root.revealSecrets
              readonly property int queuePos: root.markedKeys.indexOf(key) + 1
              readonly property string titleText: masked ? (subtitle !== "" ? previewText : "Hidden " + secret.toLowerCase()) : previewText
              readonly property string subText: masked ? (subtitle !== "" ? "••••••••••" : "") : subtitle
              readonly property string metaText: (tagsText !== "" ? "#" + tagsText.split(" ").join(" #") + "  " : "") + (app !== "" ? app + (seen || ts > 0 ? " · " : "") : "") + (seen ? "earlier" : ts > 0 ? ClipboardHistory.ago(ts, Date.now()) : "")

              readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex
              readonly property bool showGroup: pinned && group !== "" && (root.view === "all" || (root.scopeAll && root.filterText !== ""))

              width: ListView.view.width
              height: Math.max(root.rowHeight, row.subText !== "" ? root.twoLineH : 0)
              radius: root.innerRadius + root.sp(2)
              color: hasCursor ? root.selectedBackground : "transparent"

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: root.sp(10)
                anchors.rightMargin: root.sp(10)
                anchors.topMargin: root.sp(5)
                anchors.bottomMargin: root.sp(5)
                spacing: root.sp(10)

                Item {
                  Layout.preferredWidth: row.previewImage.length > 0 ? row.height - root.sp(10) : root.rs(20)
                  Layout.fillHeight: true
                  Rectangle {
                    visible: root.selectMode
                    z: 3
                    anchors.centerIn: parent
                    width: root.sp(20)
                    height: width
                    radius: root.sp(5)
                    color: row.queuePos > 0 ? root.accent : root.background
                    border.width: 2
                    border.color: row.queuePos > 0 ? root.accent : root.muted
                    Text {
                      visible: row.queuePos > 0
                      anchors.centerIn: parent
                      text: "✓"
                      color: root.accentText
                      font.pixelSize: root.fs(Style.font.caption)
                      font.bold: true
                    }
                  }
                  Rectangle {
                    visible: row.queuePos > 0 && !root.selectMode
                    z: 2
                    anchors.centerIn: parent
                    width: root.rs(20)
                    height: width
                    radius: width / 2
                    color: root.accent
                    Text {
                      anchors.centerIn: parent
                      text: row.queuePos
                      color: root.accentText
                      font.family: root.fontFamily
                      font.pixelSize: root.rf(Style.font.caption)
                      font.bold: true
                    }
                  }
                  Image {
                    visible: row.previewImage.length > 0
                    anchors.fill: parent
                    source: row.previewImage
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                  }
                  Rectangle {
                    visible: row.previewImage.length === 0 && row.swatch !== "" && !row.masked && row.queuePos === 0
                    anchors.centerIn: parent
                    width: root.sp(14)
                    height: width
                    radius: width / 2
                    color: row.swatch !== "" ? row.swatch : "transparent"
                    border.width: 1
                    border.color: root.line
                  }
                  Text {
                    visible: row.previewImage.length === 0 && (row.swatch === "" || row.masked) && row.queuePos === 0
                    anchors.centerIn: parent
                    text: row.masked ? root.glyph(0xF033E) : root.kindGlyph(row.kind)
                    color: row.hasCursor ? root.accent : root.muted
                    font.family: root.fontFamily
                    font.pixelSize: root.rf(Style.font.title)
                  }
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  Layout.alignment: Qt.AlignVCenter
                  spacing: 0
                  Text {
                    Layout.fillWidth: true
                    readonly property string marked: root.filterText !== "" && !row.masked && row.entryType !== "image" ? ClipboardHistory.highlightTitle(row.titleText, root.filterText, String(row.hasCursor ? root.selectedText : root.accent)) : ""
                    textFormat: marked !== "" ? Text.StyledText : Text.PlainText
                    text: marked !== "" ? marked : row.titleText
                    color: row.hasCursor ? root.selectedText : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: root.rf(Style.font.title)
                    font.weight: row.subtitle !== "" ? Font.Medium : Font.Normal
                    opacity: row.entryType === "image" || row.entryType === "file" ? 0.72 : 1.0
                    elide: Text.ElideRight
                    maximumLineCount: 1
                  }
                  Text {
                    visible: row.subText !== ""
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: row.subText
                    color: row.hasCursor ? root.selectedText : root.muted
                    opacity: 0.8
                    font.family: root.fontFamily
                    font.pixelSize: root.rf(Style.font.caption)
                    elide: Text.ElideRight
                    maximumLineCount: 1
                  }
                }

                Text {
                  visible: row.fav
                  text: "★"
                  color: root.accent
                  font.pixelSize: root.rf(Style.font.title)
                }

                Text {
                  visible: root.cfg.meta && !root.compactMode && row.metaText !== ""
                  text: row.metaText
                  color: row.hasCursor ? root.selectedText : root.muted
                  opacity: 0.75
                  font.family: root.fontFamily
                  font.pixelSize: root.rf(Style.font.caption)
                }

                Rectangle {
                  visible: row.showGroup
                  Layout.preferredWidth: root.rs(20)
                  Layout.preferredHeight: root.rs(20)
                  radius: Math.max(2, Math.round(root.innerRadius * 0.7))
                  color: root.badgeBg(root.groupHue(row.group))
                  Text {
                    anchors.centerIn: parent
                    text: root.groupLetter(row.group)
                    color: root.badgeFg(root.groupHue(row.group))
                    font.family: root.fontFamily
                    font.pixelSize: root.rf(Style.font.caption)
                    font.bold: true
                  }
                }

                Rectangle {
                  visible: row.index < 9 && !root.compactMode
                  Layout.preferredWidth: root.rs(20)
                  Layout.preferredHeight: root.rs(20)
                  radius: root.sp(6)
                  color: "transparent"
                  border.width: 1
                  border.color: root.line
                  Text {
                    anchors.centerIn: parent
                    text: row.index + 1
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: root.rf(Style.font.caption)
                  }
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                onPositionChanged: function(mouse) { root.selectFromPointer(row.index, row, mouse) }
                onClicked: function(mouse) {
                  if (mouse.button === Qt.MiddleButton) { root.toggleMark(displayModel.get(row.index)); return }
                  var shiftClick = (mouse.modifiers & Qt.ShiftModifier) !== 0
                  var ctrlClick = (mouse.modifiers & Qt.ControlModifier) !== 0
                  if (root.selectMode || shiftClick || ctrlClick) { root.clickMark(row.index, shiftClick); return }
                  root.cursorActive = true
                  root.selectedIndex = row.index
                  root.activateIndex(row.index)
                }
              }
            }
          }

          // Empty states
          Column {
            anchors.centerIn: parent
            width: parent.width - root.sp(40)
            spacing: root.sp(8)
            visible: displayModel.count === 0

            Text {
              text: root.glyph(0xF014C)
              color: root.accent
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: root.fs(Style.font.displayLarge)
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }
            Text {
              textFormat: Text.PlainText
              text: root.filterText !== ""
                ? "No match in " + root.groupName(root.view)
                : root.view === "recent" ? "Clipboard is empty"
                : root.view === "frequent" ? "Nothing pasted from here yet"
                : "Nothing pinned in " + root.groupName(root.view)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: root.fs(Style.font.title)
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
              wrapMode: Text.WordWrap
            }
            Text {
              textFormat: Text.PlainText
              visible: root.filterText !== "" ? root.elsewhereCount > 0 : (root.view !== "recent" && root.view !== "frequent")
              text: root.filterText !== ""
                ? root.elsewhereCount + " in other groups. Click here or press ^F to search everywhere."
                : "Select an entry in Recent and press ^P to pin it here."
              color: root.filterText !== "" ? root.accent : root.muted
              font.family: root.fontFamily
              font.pixelSize: root.fs(Style.font.caption)
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
              wrapMode: Text.WordWrap
              MouseArea {
                anchors.fill: parent
                enabled: root.filterText !== ""
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleScope()
              }
            }
          }
        }

        // Preview
        Item {
          id: prevArea
          visible: root.previewMode !== "off"
          x: root.previewMode === "right" ? root.railW + listArea.width : root.railW
          y: root.previewMode === "right" ? 0 : root.topInset + listArea.height
          width: root.previewMode === "right" ? body.width - root.railW - listArea.width : body.width - root.railW
          height: root.previewMode === "right" ? body.height : body.height - root.topInset - listArea.height
          clip: true

          Rectangle {
            id: prevPanel
            anchors.fill: parent
            anchors.topMargin: root.sp(8)
            anchors.leftMargin: root.previewMode === "right" ? root.sp(4) : root.sp(8)
            anchors.rightMargin: root.sp(10)
            anchors.bottomMargin: root.sp(8)
            radius: root.cornerRadius
            color: root.surface
          }

          Column {
            id: prevCol
            visible: root.activeRow !== null
            anchors.fill: prevPanel
            anchors.margins: root.sp(14)
            spacing: root.sp(10)

            Row {
              spacing: root.sp(8)
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.activeRow ? root.kindGlyph(root.activeRow.kind) : ""
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.title)
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.activeRow ? root.activeRow.kind : ""
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.caption)
              }
              Rectangle {
                visible: root.activeRow !== null && root.activeRow.pinned && root.activeRow.group !== ""
                anchors.verticalCenter: parent.verticalCenter
                height: root.sp(20)
                width: groupTag.implicitWidth + root.sp(12)
                radius: height / 2
                color: root.activeRow && root.activeRow.group !== "" ? root.badgeBg(root.groupHue(root.activeRow.group)) : "transparent"
                Text {
                  id: groupTag
                  anchors.centerIn: parent
                  text: root.activeRow ? root.groupName(root.activeRow.group) : ""
                  textFormat: Text.PlainText
                  color: root.activeRow && root.activeRow.group !== "" ? root.badgeFg(root.groupHue(root.activeRow.group)) : root.muted
                  font.family: root.fontFamily
                  font.pixelSize: root.fs(Style.font.caption)
                }
              }
            }

            Text {
              visible: root.activeRow !== null && (root.activeRow.app !== "" || root.activeRow.ts > 0 || root.activeRow.seen)
              text: root.activeRow ? "Copied" + (root.activeRow.app !== "" ? " from " + root.activeRow.app : "") + (root.activeRow.seen ? " earlier" : root.activeRow.ts > 0 ? " " + ClipboardHistory.ago(root.activeRow.ts, Date.now()) + " ago" : "") : ""
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: root.fs(Style.font.caption)
            }

            Rectangle {
              visible: root.activeRow !== null && root.activeRow.pinned
              width: parent.width
              height: root.sp(34)
              radius: root.innerRadius
              color: root.background
              border.width: labelInput.activeFocus ? 2 : 1
              border.color: labelInput.activeFocus ? root.accent : root.line
              TextInput {
                id: labelInput
                anchors.fill: parent
                anchors.leftMargin: root.sp(9)
                anchors.rightMargin: root.sp(9)
                verticalAlignment: TextInput.AlignVCenter
                color: root.foreground
                selectionColor: root.accent
                selectedTextColor: root.accentText
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.title)
                maximumLength: 40
                clip: true
                property string bound: root.activeRow ? root.activeRow.label : ""
                property string editKey: ""
                onActiveFocusChanged: if (activeFocus && root.activeRow) editKey = root.activeRow.key
                onBoundChanged: if (!activeFocus) text = bound
                Component.onCompleted: text = bound
                onEditingFinished: {
                  var idx = ClipboardHistory.pinIndexByKey(root.pins, editKey)
                  var pin = idx >= 0 ? ClipboardHistory.normalizeEntry(root.pins[idx]) : null
                  if (pin && text.trim() !== (pin.label || "")) root.setLabel(idx, text)
                  keyCatcher.forceActiveFocus()
                }
                Keys.onEscapePressed: { text = bound; keyCatcher.forceActiveFocus() }
                Text {
                  visible: labelInput.text.length === 0
                  anchors.fill: parent
                  verticalAlignment: Text.AlignVCenter
                  text: "Add a label (^E) so you can find it by name"
                  color: root.muted
                  font: labelInput.font
                }
              }
            }

            Flow {
              visible: root.activeRow !== null && root.activeRow.pinned
              width: parent.width
              spacing: root.sp(5)
              Repeater {
                model: root.activeRow && root.activeRow.tagsText ? root.activeRow.tagsText.split(" ") : []
                delegate: Rectangle {
                  required property string modelData
                  height: root.sp(24)
                  width: tagText.implicitWidth + root.sp(30)
                  radius: height / 2
                  color: root.selectedBackground
                  Text {
                    id: tagText
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: root.sp(10)
                    text: "#" + modelData
                    textFormat: Text.PlainText
                    color: root.selectedText
                    font.family: root.fontFamily
                    font.pixelSize: root.fs(Style.font.caption)
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: root.sp(8)
                    text: "✕"
                    color: root.selectedText
                    opacity: 0.7
                    font.pixelSize: root.fs(Style.font.caption)
                  }
                  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.removeTagFromCurrent(modelData) }
                }
              }
              Rectangle {
                height: root.sp(24)
                width: root.sp(120)
                radius: height / 2
                color: root.background
                border.width: tagInput.activeFocus ? 2 : 1
                border.color: tagInput.activeFocus ? root.accent : root.line
                TextInput {
                  id: tagInput
                  anchors.fill: parent
                  anchors.leftMargin: root.sp(10)
                  anchors.rightMargin: root.sp(10)
                  verticalAlignment: TextInput.AlignVCenter
                  color: root.foreground
                  selectionColor: root.accent
                  selectedTextColor: root.accentText
                  font.family: root.fontFamily
                  font.pixelSize: root.fs(Style.font.caption)
                  maximumLength: 40
                  clip: true
                  onAccepted: { root.addTagsToCurrent(text); text = ""; keyCatcher.forceActiveFocus() }
                  Keys.onEscapePressed: { text = ""; keyCatcher.forceActiveFocus() }
                  Text {
                    visible: tagInput.text.length === 0
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    text: "+ tag (^⇧E)"
                    color: root.muted
                    font: tagInput.font
                  }
                }
              }
            }

            Rectangle {
              visible: root.activeRow !== null && root.activeRow.swatch !== "" && root.activeRow.previewImage === ""
              width: parent.width
              height: root.sp(70)
              radius: root.innerRadius
              color: root.activeRow && root.activeRow.swatch !== "" ? root.activeRow.swatch : "transparent"
              border.width: 1
              border.color: root.line
            }

            Text {
              textFormat: Text.PlainText
              visible: root.activeRow !== null && !root.activeRow.previewImage && !root.editing
              width: parent.width
              height: Math.max(root.sp(40), prevCol.height - y - actionRow.height - prevCol.spacing)
              text: root.activeRow ? (root.activeRow.secret !== "" && root.cfg.mask && !root.revealSecrets ? "Hidden " + root.activeRow.secret.toLowerCase() + ". Press ^R to reveal." : root.activeRow.fullText) : ""
              color: root.foreground
              font.family: root.activeRow && root.activeRow.kind === "code" ? Style.font.menuFamily : root.fontFamily
              font.pixelSize: root.fs(Style.font.title)
              wrapMode: Text.WrapAnywhere
              elide: Text.ElideRight
              verticalAlignment: Text.AlignTop
              MouseArea {
                anchors.fill: parent
                onDoubleClicked: root.beginEdit()
              }
            }

            Rectangle {
              id: editBox
              visible: root.editing && root.activeRow !== null
              width: parent.width
              height: Math.max(root.sp(60), prevCol.height - y - editRow.height - prevCol.spacing)
              radius: root.innerRadius
              color: root.background
              border.width: 2
              border.color: root.accent
              clip: true

              Flickable {
                id: editFlick
                anchors.fill: parent
                anchors.margins: root.sp(9)
                clip: true
                contentWidth: width
                contentHeight: editInput.height
                boundsBehavior: Flickable.StopAtBounds

                function follow(r) {
                  if (contentY > r.y) contentY = r.y
                  else if (contentY + height < r.y + r.height) contentY = r.y + r.height - height
                }

                TextEdit {
                  id: editInput
                  textFormat: TextEdit.PlainText
                  width: editFlick.width
                  height: Math.max(implicitHeight, editFlick.height)
                  color: root.foreground
                  selectionColor: root.accent
                  selectedTextColor: root.accentText
                  selectByMouse: true
                  persistentSelection: true
                  font.family: root.activeRow && root.activeRow.kind === "code" ? Style.font.menuFamily : root.fontFamily
                  font.pixelSize: root.fs(Style.font.title)
                  wrapMode: TextEdit.WrapAnywhere
                  verticalAlignment: TextEdit.AlignTop
                  onCursorRectangleChanged: editFlick.follow(cursorRectangle)
                  onTextChanged: root.editDiscardArmed = false
                  Keys.onPressed: function(event) {
                    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
                    if (event.key === Qt.Key_Escape) { root.escapeEdit(); event.accepted = true }
                    else if (ctrl && event.key === Qt.Key_S) { root.finishEdit("save"); event.accepted = true }
                    else if (ctrl && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) { root.finishEdit("paste"); event.accepted = true }
                  }
                }
              }
            }

            Image {
              visible: root.activeRow !== null && !!root.activeRow.previewImage
              width: parent.width
              height: Math.max(root.sp(60), prevCol.height - y - actionRow.height - prevCol.spacing)
              source: root.activeRow ? root.activeRow.previewImage : ""
              fillMode: Image.PreserveAspectFit
              verticalAlignment: Image.AlignTop
              asynchronous: true
              smooth: true
            }

            Flow {
              id: editRow
              visible: root.editing
              width: parent.width
              spacing: root.sp(6)

              Repeater {
                model: [
                  { id: "paste", label: "Paste edit", hint: "^↵", primary: true },
                  { id: "save", label: root.activeRow && root.activeRow.pinned ? "Save" : "Copy edit", hint: "^S", primary: false },
                  { id: "cancel", label: "Cancel", hint: "Esc", primary: false }
                ]
                delegate: Rectangle {
                  required property var modelData
                  height: root.sp(30)
                  width: editBtnLabel.implicitWidth + root.sp(22)
                  radius: root.innerRadius
                  color: modelData.primary ? root.accent : (editBtnMouse.containsMouse ? root.selectedBackground : "transparent")
                  border.width: modelData.primary ? 0 : 1
                  border.color: root.line
                  Text {
                    id: editBtnLabel
                    anchors.centerIn: parent
                    text: modelData.label + "  " + modelData.hint
                    color: modelData.primary ? root.accentText : (editBtnMouse.containsMouse ? root.selectedText : root.foreground)
                    font.family: root.fontFamily
                    font.pixelSize: root.fs(Style.font.caption)
                  }
                  MouseArea {
                    id: editBtnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (modelData.id === "cancel") root.cancelEdit()
                      else root.finishEdit(modelData.id)
                    }
                  }
                }
              }
            }

            Flow {
              id: actionRow
              visible: !root.editing
              width: parent.width
              spacing: root.sp(6)

              Repeater {
                model: [
                  { id: "paste", label: "Paste", hint: "↵", primary: true },
                  { id: "copy", label: "Copy", hint: "⇧↵", primary: false },
                  { id: "edit", label: "Edit", hint: "F4", primary: false },
                  { id: "pin", label: root.activeRow && root.activeRow.pinned ? "Unpin" : "Pin", hint: "^P", primary: false },
                  { id: "move", label: "Move", hint: "^M", primary: false },
                  { id: "fav", label: root.activeRow && root.activeRow.fav ? "Unfavorite" : "Favorite", hint: "^D", primary: false },
                  { id: "xform", label: "Transform", hint: "^T", primary: false },
                  { id: "ocr", label: "Text from image", hint: "^O", primary: false }
                ]
                delegate: Rectangle {
                  required property var modelData
                  visible: (modelData.id !== "move" || (root.activeRow !== null && root.activeRow.pinned)) && ((modelData.id !== "xform" && modelData.id !== "edit") || (root.activeRow !== null && root.activeRow.entryType !== "image")) && (modelData.id !== "ocr" || (root.activeRow !== null && root.activeRow.entryType === "image"))
                  height: root.sp(30)
                  width: visible ? btnLabel.implicitWidth + root.sp(22) : 0
                  radius: root.innerRadius
                  color: modelData.primary ? root.accent : (btnMouse.containsMouse ? root.selectedBackground : "transparent")
                  border.width: modelData.primary ? 0 : 1
                  border.color: root.line
                  Text {
                    id: btnLabel
                    anchors.centerIn: parent
                    text: modelData.label + "  " + modelData.hint
                    color: modelData.primary ? root.accentText : (btnMouse.containsMouse ? root.selectedText : root.foreground)
                    font.family: root.fontFamily
                    font.pixelSize: root.fs(Style.font.caption)
                  }
                  MouseArea {
                    id: btnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (modelData.id === "paste") root.activateIndex(root.selectedIndex)
                      else if (modelData.id === "copy") root.copyIndex(root.selectedIndex)
                      else if (modelData.id === "edit") root.beginEdit()
                      else if (modelData.id === "pin") root.pinSelected()
                      else if (modelData.id === "fav") root.toggleFav()
                      else if (modelData.id === "xform") root.openXform()
                      else if (modelData.id === "ocr") root.ocrSelected()
                      else root.openMove()
                    }
                  }
                }
              }
            }
          }
        }
      }

      // ---- screenshots tab ---------------------------------------------
      Help {
        id: helpPanel
        host: root
        visible: root.helpOpen
        z: 20
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
      }

      Shots {
        id: shotsTab
        host: root
        visible: root.tab === "shots"
        anchors.top: header.bottom
        anchors.bottom: footer.top
        anchors.left: parent.left
        anchors.right: parent.right
      }

      // ---- group name box ----------------------------------------------
      Rectangle {
        id: groupEditBox
        visible: root.groupEditOpen
        z: 7
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: footer.top
        anchors.bottomMargin: root.sp(10)
        width: Math.min(parent.width - root.sp(32), root.sp(320))
        height: root.sp(44)
        radius: root.cornerRadius
        color: root.surface
        border.width: 2
        border.color: root.accent
        TextInput {
          id: groupInput
          anchors.fill: parent
          anchors.leftMargin: root.sp(14)
          anchors.rightMargin: root.sp(14)
          verticalAlignment: TextInput.AlignVCenter
          color: root.foreground
          selectionColor: root.accent
          selectedTextColor: root.accentText
          font.family: root.fontFamily
          font.pixelSize: root.fs(Style.font.title)
          maximumLength: 20
          clip: true
          onAccepted: root.finishGroupEdit(true)
          Keys.onEscapePressed: root.finishGroupEdit(false)
          Text {
            visible: groupInput.text.length === 0
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            text: root.groupEditMode === "rename" ? "Rename group, then Enter" : "New group name, then Enter"
            color: root.muted
            font: groupInput.font
          }
        }
      }

      // ---- move popover ------------------------------------------------
      Rectangle {
        id: movePop
        visible: root.moveOpen
        z: 7
        anchors.right: parent.right
        anchors.rightMargin: root.sp(16)
        anchors.bottom: footer.top
        anchors.bottomMargin: root.sp(10)
        width: root.sp(250)
        height: moveCol.implicitHeight + root.sp(12)
        radius: root.cornerRadius
        color: root.surface
        border.width: 1
        border.color: root.line

        Column {
          id: moveCol
          anchors.fill: parent
          anchors.margins: root.sp(6)
          spacing: root.sp(1)

          Text {
            text: "Move to"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.caption)
            leftPadding: root.sp(8)
            topPadding: root.sp(4)
            bottomPadding: root.sp(4)
          }

          Repeater {
            model: root.groups
            delegate: Rectangle {
              required property var modelData
              required property int index
              width: moveCol.width
              height: root.sp(32)
              radius: root.innerRadius
              color: moveItemMouse.containsMouse ? root.selectedBackground : "transparent"
              Row {
                anchors.fill: parent
                anchors.leftMargin: root.sp(8)
                spacing: root.sp(8)
                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: root.sp(20)
                  height: width
                  radius: Math.max(2, Math.round(root.innerRadius * 0.7))
                  color: root.badgeBg(modelData.h)
                  Text {
                    anchors.centerIn: parent
                    text: modelData.name.charAt(0).toUpperCase()
                    textFormat: Text.PlainText
                    color: root.badgeFg(modelData.h)
                    font.family: root.fontFamily
                    font.pixelSize: root.fs(Style.font.caption)
                    font.bold: true
                  }
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - root.sp(60)
                  text: modelData.name
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: root.fs(Style.font.title)
                  elide: Text.ElideRight
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: index < 9
                  text: index + 1
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: root.fs(Style.font.caption)
                }
              }
              MouseArea {
                id: moveItemMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.moveTo(modelData.id)
              }
            }
          }

          Rectangle {
            width: moveCol.width
            height: root.sp(32)
            radius: root.innerRadius
            color: unpinMouse.containsMouse ? root.selectedBackground : "transparent"
            Text {
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: root.sp(8)
              text: "No group (0)"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: root.fs(Style.font.title)
            }
            MouseArea {
              id: unpinMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.moveTo("")
            }
          }
        }
      }

      // ---- transform menu ----------------------------------------------
      Rectangle {
        id: xformPop
        visible: root.xformOpen
        z: 7
        anchors.right: parent.right
        anchors.rightMargin: root.sp(16)
        anchors.bottom: footer.top
        anchors.bottomMargin: root.sp(10)
        width: root.sp(270)
        height: xformCol.implicitHeight + root.sp(12)
        radius: root.cornerRadius
        color: root.surface
        border.width: 1
        border.color: root.line

        Column {
          id: xformCol
          anchors.fill: parent
          anchors.margins: root.sp(6)
          spacing: root.sp(1)
          Text {
            text: "Paste as"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.caption)
            leftPadding: root.sp(8)
            topPadding: root.sp(4)
            bottomPadding: root.sp(4)
          }
          Repeater {
            model: ClipboardHistory.transformList
            delegate: Rectangle {
              required property var modelData
              required property int index
              width: xformCol.width
              height: root.sp(30)
              radius: root.innerRadius
              color: xformMouse.containsMouse ? root.selectedBackground : "transparent"
              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: root.sp(10)
                text: modelData.label
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.title)
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: root.sp(10)
                text: index === 9 ? 0 : index + 1
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.caption)
              }
              MouseArea {
                id: xformMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.applyXform(index)
              }
            }
          }
        }
      }

      // ---- template prompt ---------------------------------------------
      Rectangle {
        id: askBox
        visible: root.askOpen
        z: 7
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: footer.top
        anchors.bottomMargin: root.sp(10)
        width: Math.min(parent.width - root.sp(32), root.sp(380))
        height: root.sp(60)
        radius: root.cornerRadius
        color: root.surface
        border.width: 2
        border.color: root.accent
        Text {
          anchors.left: parent.left
          anchors.leftMargin: root.sp(14)
          anchors.top: parent.top
          anchors.topMargin: root.sp(7)
          text: root.askNames.length > 0 ? root.askNames[Math.min(root.askIdx, root.askNames.length - 1)] + (root.askNames.length > 1 ? "  (" + (root.askIdx + 1) + "/" + root.askNames.length + ")" : "") : ""
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: root.fs(Style.font.caption)
        }
        TextInput {
          id: askInput
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.leftMargin: root.sp(14)
          anchors.rightMargin: root.sp(14)
          anchors.bottomMargin: root.sp(8)
          height: root.sp(26)
          verticalAlignment: TextInput.AlignVCenter
          color: root.foreground
          selectionColor: root.accent
          selectedTextColor: root.accentText
          font.family: root.fontFamily
          font.pixelSize: root.fs(Style.font.title)
          clip: true
          onAccepted: root.answerAsk()
          Keys.onEscapePressed: root.cancelAsk()
        }
      }

      // ---- selection bar -------------------------------------------------
      Rectangle {
        id: queueBar
        visible: root.markedKeys.length > 0
        z: 6
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footer.top
        anchors.leftMargin: root.contentMargin
        anchors.rightMargin: root.contentMargin
        height: root.sp(38)
        radius: root.cornerRadius
        color: root.accent
        Row {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: root.sp(14)
          spacing: root.sp(8)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.markedKeys.length + " selected"
            color: root.accentText
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.caption)
            font.bold: true
          }
          Repeater {
            model: root.compactMode
              ? [{ id: "del", label: "Delete" }, { id: "clear", label: "Clear" }]
              : [{ id: "del", label: "Delete  Del" }, { id: "queue", label: "Paste queue  ^↵" }, { id: "all", label: "All shown  ^A" }, { id: "clear", label: "Clear  Esc" }]
            delegate: Rectangle {
              required property var modelData
              height: root.sp(26)
              width: barLabel.implicitWidth + root.sp(20)
              radius: height / 2
              color: modelData.id === "del" ? root.accentText : "transparent"
              border.width: 1
              border.color: root.accentText
              Text {
                id: barLabel
                anchors.centerIn: parent
                text: modelData.label
                color: modelData.id === "del" ? root.accent : root.accentText
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.caption)
                font.bold: modelData.id === "del"
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (modelData.id === "del") root.deleteMarked()
                  else if (modelData.id === "queue") root.pasteQueue("tab")
                  else if (modelData.id === "all") root.markAllShown()
                  else { root.markedKeys = []; root.lastMarkIndex = -1 }
                }
              }
            }
          }
        }
      }

      // ---- clean up menu ---------------------------------------------------
      Rectangle {
        visible: root.cleanOpen
        z: 7
        anchors.right: parent.right
        anchors.rightMargin: root.sp(16)
        anchors.bottom: footer.top
        anchors.bottomMargin: root.sp(10)
        width: root.sp(330)
        height: cleanCol.implicitHeight + root.sp(12)
        radius: root.cornerRadius
        color: root.surface
        border.width: 1
        border.color: root.line
        Column {
          id: cleanCol
          anchors.fill: parent
          anchors.margins: root.sp(6)
          spacing: root.sp(1)
          Text {
            text: "Clean up (selects them, you confirm)"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.caption)
            leftPadding: root.sp(8)
            topPadding: root.sp(4)
            bottomPadding: root.sp(4)
          }
          Repeater {
            model: [
              { id: "old", label: "Unused for 30 days", n: root.cleanCounts.old },
              { id: "secrets", label: "Look like secrets", n: root.cleanCounts.secrets },
              { id: "big", label: "Very large (over 20 KB)", n: root.cleanCounts.big }
            ]
            delegate: Rectangle {
              required property var modelData
              required property int index
              width: cleanCol.width
              height: root.sp(32)
              radius: root.innerRadius
              color: cleanMouse.containsMouse ? root.selectedBackground : "transparent"
              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: root.sp(10)
                text: (index + 1) + "   " + modelData.label
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.title)
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: root.sp(10)
                text: modelData.n
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.caption)
              }
              MouseArea {
                id: cleanMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.applyCleanup(modelData.id)
              }
            }
          }
        }
      }

      // ---- toast -------------------------------------------------------
      Rectangle {
        id: toast
        visible: root.toastText !== ""
        z: 8
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: footer.top
        anchors.bottomMargin: root.sp(10)
        width: Math.min(parent.width - root.sp(32), toastRow.implicitWidth + root.sp(28))
        height: root.sp(36)
        radius: root.cornerRadius
        color: root.foreground

        Row {
          id: toastRow
          anchors.centerIn: parent
          spacing: root.sp(16)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.toastText
            color: root.background
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.caption)
          }
          Text {
            visible: root.toastUndoable
            anchors.verticalCenter: parent.verticalCenter
            text: "Undo"
            color: root.background
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.caption)
            font.underline: true
            MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: root.undoToast() }
          }
          Text {
            visible: root.toastMovable
            anchors.verticalCenter: parent.verticalCenter
            text: "Move…"
            color: root.background
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.caption)
            font.underline: true
            MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: { toastTimer.stop(); root.toastText = ""; root.openMove() } }
          }
        }
      }

      // ---- settings drawer --------------------------------------------
      Rectangle {
        id: drawer
        visible: root.settingsOpen
        z: 9
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: Math.min(root.sp(310), parent.width)
        color: root.surface
        radius: root.cornerRadius + root.sp(4)

        Rectangle {
          anchors.left: parent.left
          width: Style.normalBorderWidth
          height: parent.height
          color: root.line
        }

        MouseArea { anchors.fill: parent }

        Item {
          id: drawerHead
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: root.sp(48)
          Text {
            anchors.left: parent.left
            anchors.leftMargin: root.sp(16)
            anchors.verticalCenter: parent.verticalCenter
            text: "Appearance"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.title)
            font.bold: true
          }
          Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: root.sp(10)
            anchors.verticalCenter: parent.verticalCenter
            width: root.sp(30)
            height: width
            radius: root.innerRadius
            color: closeMouse.containsMouse ? root.selectedBackground : "transparent"
            Text {
              anchors.centerIn: parent
              text: root.glyph(0xF0156)
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: root.fs(Style.font.title)
            }
            MouseArea {
              id: closeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.settingsOpen = false
            }
          }
          Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: Style.normalBorderWidth
            color: root.line
          }
        }

        Flickable {
          anchors.top: drawerHead.bottom
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          contentHeight: drawerCol.implicitHeight + root.sp(28)
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: drawerCol
            x: root.sp(16)
            y: root.sp(14)
            width: parent.width - root.sp(32)
            spacing: root.sp(16)

            // Theme
            Column {
              width: parent.width
              spacing: root.sp(7)
              Text { text: "Theme"; color: root.muted; font.family: root.fontFamily; font.pixelSize: root.fs(Style.font.caption) }
              Flow {
                width: parent.width
                spacing: root.sp(6)
                Repeater {
                  model: root.themeChoices
                  delegate: Rectangle {
                    required property var modelData
                    readonly property bool chosen: root.cfg.theme === modelData.id
                    width: Math.floor((drawerCol.width - root.sp(12)) / 3)
                    height: root.sp(56)
                    radius: root.innerRadius
                    color: "transparent"
                    border.width: chosen ? 2 : 1
                    border.color: chosen ? root.accent : root.line
                    Column {
                      anchors.fill: parent
                      anchors.margins: root.sp(5)
                      spacing: root.sp(4)
                      Rectangle {
                        width: parent.width
                        height: root.sp(24)
                        radius: Math.max(2, root.innerRadius - 2)
                        clip: true
                        color: modelData.bg !== "" ? modelData.bg : root.background
                        border.width: 1
                        border.color: root.line
                        Row {
                          anchors.fill: parent
                          Rectangle { width: parent.width / 3; height: parent.height; color: "transparent" }
                          Rectangle { width: parent.width / 3; height: parent.height; color: modelData.sel !== "" ? modelData.sel : root.selectedBackground }
                          Rectangle { width: parent.width / 3; height: parent.height; color: modelData.accent !== "" ? modelData.accent : root.selectedText }
                        }
                      }
                      Text {
                        width: parent.width
                        text: modelData.name
                        textFormat: Text.PlainText
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: root.fs(Style.font.caption)
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                      }
                    }
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.setCfg("theme", modelData.id)
                    }
                  }
                }
              }
            }

            // Accent
            Column {
              width: parent.width
              spacing: root.sp(7)
              Text { text: "Accent"; color: root.muted; font.family: root.fontFamily; font.pixelSize: root.fs(Style.font.caption) }
              Flow {
                width: parent.width
                spacing: root.sp(8)
                Rectangle {
                  width: root.sp(26)
                  height: width
                  radius: width / 2
                  color: "transparent"
                  border.width: root.cfg.accent === "" ? 2 : 1
                  border.color: root.cfg.accent === "" ? root.foreground : root.muted
                  Text { anchors.centerIn: parent; text: "T"; color: root.muted; font.family: root.fontFamily; font.pixelSize: root.fs(Style.font.caption) }
                  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setCfg("accent", "") }
                }
                Repeater {
                  model: root.accentChoices
                  delegate: Rectangle {
                    required property string modelData
                    width: root.sp(26)
                    height: width
                    radius: width / 2
                    color: modelData
                    border.width: root.cfg.accent === modelData ? 2 : 0
                    border.color: root.foreground
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setCfg("accent", modelData) }
                  }
                }
              }
            }

            // Row density slider
            Column {
              width: parent.width
              spacing: root.sp(8)
              Text {
                text: "Interface size  " + Math.round(root.rowScale * 100) + "%"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.caption)
              }
              Item {
                id: densitySlider
                width: parent.width
                height: root.sp(28)
                readonly property real frac: Math.max(0, Math.min(1, (root.rowScale * 100 - 40) / 140))
                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width
                  height: root.sp(6)
                  radius: height / 2
                  color: root.line
                  Rectangle {
                    width: parent.width * densitySlider.frac
                    height: parent.height
                    radius: parent.radius
                    color: root.accent
                  }
                }
                Rectangle {
                  x: densitySlider.frac * (parent.width - width)
                  anchors.verticalCenter: parent.verticalCenter
                  width: root.sp(20)
                  height: width
                  radius: width / 2
                  color: root.accent
                  border.width: 2
                  border.color: root.surface
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  function setFromX(x) {
                    var f = Math.max(0, Math.min(1, x / width))
                    root.dragScale = Math.round((40 + f * 140) / 5) * 5
                  }
                  onPressed: function(mouse) { setFromX(mouse.x) }
                  onPositionChanged: function(mouse) { if (pressed) setFromX(mouse.x) }
                  onReleased: {
                    var v = root.dragScale
                    root.dragScale = 0
                    if (v > 0) root.setCfg("rowScale", v)
                  }
                }
              }
              Text {
                width: parent.width
                text: "Smaller ← → larger. Everything in the app scales, including text. ^⇧↓ and ^⇧↑ nudge it from the keyboard."
                wrapMode: Text.WordWrap
                color: root.muted
                opacity: 0.8
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.caption)
              }
            }

            // Option sections
            Repeater {
              model: root.settingSections
              delegate: Column {
                id: sec
                required property var modelData
                width: drawerCol.width
                spacing: root.sp(7)
                Text { text: sec.modelData.label; color: root.muted; font.family: root.fontFamily; font.pixelSize: root.fs(Style.font.caption) }
                Flow {
                  width: parent.width
                  spacing: root.sp(6)
                  Repeater {
                    model: sec.modelData.opts
                    delegate: Rectangle {
                      required property var modelData
                      readonly property bool chosen: root.cfg[sec.modelData.key] === modelData.v
                      height: root.sp(30)
                      width: optText.implicitWidth + root.sp(22)
                      radius: root.innerRadius
                      color: chosen ? root.selectedBackground : "transparent"
                      border.width: chosen ? 2 : 1
                      border.color: chosen ? root.accent : root.line
                      Text {
                        id: optText
                        anchors.centerIn: parent
                        text: modelData.l
                        color: chosen ? root.selectedText : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: root.fs(Style.font.caption)
                      }
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setCfg(sec.modelData.key, modelData.v)
                      }
                    }
                  }
                }
              }
            }

            Rectangle {
              height: root.sp(30)
              width: resetText.implicitWidth + root.sp(22)
              radius: root.innerRadius
              color: resetMouse.containsMouse ? root.selectedBackground : "transparent"
              border.width: 1
              border.color: root.line
              Text { id: resetText; anchors.centerIn: parent; text: "Reset appearance"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: root.fs(Style.font.caption) }
              MouseArea { id: resetMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.resetCfg() }
            }

            // ---- never keep copies from these apps
            Column {
              width: parent.width
              spacing: root.sp(7)
              Text { text: "Never keep copies from these apps"; color: root.muted; font.family: root.fontFamily; font.pixelSize: root.fs(Style.font.caption) }
              Flow {
                width: parent.width
                spacing: root.sp(6)
                Repeater {
                  model: root.cfg.excludeApps || []
                  delegate: Rectangle {
                    required property string modelData
                    height: root.sp(26)
                    width: exText.implicitWidth + root.sp(30)
                    radius: height / 2
                    color: root.selectedBackground
                    Text { id: exText; anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: root.sp(10); text: modelData; color: root.selectedText; font.family: root.fontFamily; font.pixelSize: root.fs(Style.font.caption) }
                    Text { anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; anchors.rightMargin: root.sp(9); text: "✕"; color: root.selectedText; opacity: 0.8; font.pixelSize: root.fs(Style.font.caption) }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.removeExclude(modelData) }
                  }
                }
              }
              Rectangle {
                width: parent.width
                height: root.sp(32)
                radius: root.innerRadius
                color: root.background
                border.width: excludeInput.activeFocus ? 2 : 1
                border.color: excludeInput.activeFocus ? root.accent : root.line
                TextInput {
                  id: excludeInput
                  anchors.fill: parent
                  anchors.leftMargin: root.sp(9)
                  anchors.rightMargin: root.sp(9)
                  verticalAlignment: TextInput.AlignVCenter
                  color: root.foreground
                  selectionColor: root.accent
                  selectedTextColor: root.accentText
                  font.family: root.fontFamily
                  font.pixelSize: root.fs(Style.font.title)
                  clip: true
                  onAccepted: { root.addExclude(text); text = ""; keyCatcher.forceActiveFocus() }
                  Keys.onEscapePressed: keyCatcher.forceActiveFocus()
                  Text { visible: excludeInput.text.length === 0; anchors.fill: parent; verticalAlignment: Text.AlignVCenter; text: "App name, then Enter"; color: root.muted; font: excludeInput.font }
                }
              }
              Flow {
                width: parent.width
                spacing: root.sp(6)
                Repeater {
                  model: ["1password", "bitwarden", "keepassxc"]
                  delegate: Rectangle {
                    required property string modelData
                    height: root.sp(26)
                    width: qaText.implicitWidth + root.sp(20)
                    radius: height / 2
                    color: "transparent"
                    border.width: 1
                    border.color: root.line
                    Text { id: qaText; anchors.centerIn: parent; text: "+ " + modelData; color: root.muted; font.family: root.fontFamily; font.pixelSize: root.fs(Style.font.caption) }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.addExclude(modelData) }
                  }
                }
              }
            }

            // ---- backup and import
            Column {
              width: parent.width
              spacing: root.sp(7)
              Text { text: "Backup and import"; color: root.muted; font.family: root.fontFamily; font.pixelSize: root.fs(Style.font.caption) }
              Rectangle {
                height: root.sp(30)
                width: exportText.implicitWidth + root.sp(22)
                radius: root.innerRadius
                color: exportMouse.containsMouse ? root.selectedBackground : "transparent"
                border.width: 1
                border.color: root.line
                Text { id: exportText; anchors.centerIn: parent; text: "Export pins and groups"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: root.fs(Style.font.caption) }
                MouseArea { id: exportMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.exportBackup() }
              }
              Rectangle {
                width: parent.width
                height: root.sp(32)
                radius: root.innerRadius
                color: root.background
                border.width: importInput.activeFocus ? 2 : 1
                border.color: importInput.activeFocus ? root.accent : root.line
                TextInput {
                  id: importInput
                  anchors.fill: parent
                  anchors.leftMargin: root.sp(9)
                  anchors.rightMargin: root.sp(9)
                  verticalAlignment: TextInput.AlignVCenter
                  color: root.foreground
                  selectionColor: root.accent
                  selectedTextColor: root.accentText
                  font.family: root.fontFamily
                  font.pixelSize: root.fs(Style.font.title)
                  clip: true
                  Component.onCompleted: text = root.cfg.importPath || ""
                  onEditingFinished: { root.setCfg("importPath", text); keyCatcher.forceActiveFocus() }
                  Keys.onEscapePressed: keyCatcher.forceActiveFocus()
                  Text { visible: importInput.text.length === 0; anchors.fill: parent; verticalAlignment: Text.AlignVCenter; text: "Path of a backup file"; color: root.muted; font: importInput.font }
                }
              }
              Rectangle {
                height: root.sp(30)
                width: importText.implicitWidth + root.sp(22)
                radius: root.innerRadius
                color: importMouse.containsMouse ? root.selectedBackground : "transparent"
                border.width: 1
                border.color: root.line
                Text { id: importText; anchors.centerIn: parent; text: "Import (merge)"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: root.fs(Style.font.caption) }
                MouseArea { id: importMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.setCfg("importPath", importInput.text); root.runImport() } }
              }
            }

            // ---- sync between machines
            Column {
              width: parent.width
              spacing: root.sp(7)
              Text { text: "Sync between machines"; color: root.muted; font.family: root.fontFamily; font.pixelSize: root.fs(Style.font.caption) }
              Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Pick a folder that your Google Drive, Syncthing or Dropbox keeps in step on both machines."
                color: root.muted
                opacity: 0.8
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.caption)
              }
              Rectangle {
                width: parent.width
                height: root.sp(32)
                radius: root.innerRadius
                color: root.background
                border.width: folderInput.activeFocus ? 2 : 1
                border.color: folderInput.activeFocus ? root.accent : root.line
                TextInput {
                  id: folderInput
                  anchors.fill: parent
                  anchors.leftMargin: root.sp(9)
                  anchors.rightMargin: root.sp(9)
                  verticalAlignment: TextInput.AlignVCenter
                  color: root.foreground
                  selectionColor: root.accent
                  selectedTextColor: root.accentText
                  font.family: root.fontFamily
                  font.pixelSize: root.fs(Style.font.title)
                  clip: true
                  Component.onCompleted: text = root.cfg.syncFolder || ""
                  onEditingFinished: { if (text !== (root.cfg.syncFolder || "")) root.setCfg("syncFolder", text); keyCatcher.forceActiveFocus() }
                  Keys.onEscapePressed: keyCatcher.forceActiveFocus()
                  Text { visible: folderInput.text.length === 0; anchors.fill: parent; verticalAlignment: Text.AlignVCenter; text: "Folder, e.g. ~/GoogleDrive/clipboard"; color: root.muted; font: folderInput.font }
                }
              }
              Rectangle {
                visible: (root.cfg.syncFolder || "") !== ""
                height: root.sp(30)
                width: folderSyncText.implicitWidth + root.sp(22)
                radius: root.innerRadius
                color: folderSyncMouse.containsMouse ? root.selectedBackground : "transparent"
                border.width: 1
                border.color: root.line
                Text { id: folderSyncText; anchors.centerIn: parent; text: "Sync now"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: root.fs(Style.font.caption) }
                MouseArea { id: folderSyncMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: syncFile.reload() }
              }
              Text {
                visible: root.statusMsg !== ""
                width: parent.width
                wrapMode: Text.WordWrap
                text: root.statusMsg
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.caption)
              }
              Text { text: "Or over SSH"; color: root.muted; font.family: root.fontFamily; font.pixelSize: root.fs(Style.font.caption) }
              Rectangle {
                width: parent.width
                height: root.sp(32)
                radius: root.innerRadius
                color: root.background
                border.width: peerInput.activeFocus ? 2 : 1
                border.color: peerInput.activeFocus ? root.accent : root.line
                TextInput {
                  id: peerInput
                  anchors.fill: parent
                  anchors.leftMargin: root.sp(9)
                  anchors.rightMargin: root.sp(9)
                  verticalAlignment: TextInput.AlignVCenter
                  color: root.foreground
                  selectionColor: root.accent
                  selectedTextColor: root.accentText
                  font.family: root.fontFamily
                  font.pixelSize: root.fs(Style.font.title)
                  clip: true
                  Component.onCompleted: text = root.cfg.syncPeer || ""
                  onEditingFinished: { if (text !== (root.cfg.syncPeer || "")) root.setCfg("syncPeer", text); keyCatcher.forceActiveFocus() }
                  Keys.onEscapePressed: keyCatcher.forceActiveFocus()
                  Text { visible: peerInput.text.length === 0; anchors.fill: parent; verticalAlignment: Text.AlignVCenter; text: "SSH host, e.g. laptop"; color: root.muted; font: peerInput.font }
                }
              }
              Rectangle {
                visible: (root.cfg.syncPeer || "") !== ""
                height: root.sp(30)
                width: syncText.implicitWidth + root.sp(22)
                radius: root.innerRadius
                color: syncMouse.containsMouse ? root.selectedBackground : "transparent"
                border.width: 1
                border.color: root.line
                Text { id: syncText; anchors.centerIn: parent; text: root.syncBusy ? "Syncing…" : "Sync over SSH"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: root.fs(Style.font.caption) }
                MouseArea { id: syncMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.runSync() }
              }
              Text {
                visible: root.syncStatus !== ""
                width: parent.width
                wrapMode: Text.WordWrap
                text: root.syncStatus
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.caption)
              }
            }

            Rectangle {
              height: root.sp(30)
              width: resetSizeText.implicitWidth + root.sp(22)
              radius: root.innerRadius
              color: resetSizeMouse.containsMouse ? root.selectedBackground : "transparent"
              border.width: 1
              border.color: root.line
              Text { id: resetSizeText; anchors.centerIn: parent; text: "Reset this window size"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: root.fs(Style.font.caption) }
              MouseArea { id: resetSizeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.resetSize() }
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: "Drag any edge or corner to resize; double-click an edge to reset. ^+ and ^- change size. Groups: ^N new, F2 rename, ^Delete delete."
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: root.fs(Style.font.caption)
            }
          }
        }
      }
    }

    // Resize handles around the card. The card is centered, so dragging an
    // edge grows both sides; the size is remembered per window mode.
    Repeater {
      model: [
        { sx: -1, sy: 0, c: Qt.SizeHorCursor }, { sx: 1, sy: 0, c: Qt.SizeHorCursor },
        { sx: 0, sy: -1, c: Qt.SizeVerCursor }, { sx: 0, sy: 1, c: Qt.SizeVerCursor },
        { sx: -1, sy: -1, c: Qt.SizeFDiagCursor }, { sx: 1, sy: 1, c: Qt.SizeFDiagCursor },
        { sx: 1, sy: -1, c: Qt.SizeBDiagCursor }, { sx: -1, sy: 1, c: Qt.SizeBDiagCursor }
      ]
      delegate: Item {
        id: handle
        required property var modelData
        readonly property real hw: root.sp(14)
        x: modelData.sx < 0 ? card.x - hw / 2 : modelData.sx > 0 ? card.x + card.width - hw / 2 : card.x + hw
        y: modelData.sy < 0 ? card.y - hw / 2 : modelData.sy > 0 ? card.y + card.height - hw / 2 : card.y + hw
        width: modelData.sx === 0 ? card.width - hw * 2 : hw
        height: modelData.sy === 0 ? card.height - hw * 2 : hw
        z: 5

        MouseArea {
          id: grab
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton
          cursorShape: handle.modelData.c
          property real startX: 0
          property real startY: 0
          property real startW: 0
          property real startH: 0
          onPressed: function(mouse) {
            var p = mapToItem(panel.contentItem, mouse.x, mouse.y)
            startX = p.x; startY = p.y; startW = card.width; startH = card.height
          }
          onPositionChanged: function(mouse) {
            if (!pressed) return
            var p = mapToItem(panel.contentItem, mouse.x, mouse.y)
            if (handle.modelData.sx !== 0)
              root.dragW = Math.round(Math.max(Math.min(startW + 2 * handle.modelData.sx * (p.x - startX), root.maxW), Math.min(root.minW, root.maxW)))
            if (handle.modelData.sy !== 0)
              root.dragH = Math.round(Math.max(Math.min(startH + 2 * handle.modelData.sy * (p.y - startY), root.maxH), Math.min(root.minH, root.maxH)))
          }
          onReleased: root.commitSize()
          onDoubleClicked: root.resetSize()
        }
      }
    }
  }
}
