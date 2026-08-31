import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// Omarchy Pets — a Codex-Pets-format desktop companion for the Omarchy shell.
//
// One transparent layer per screen; only the sprite, its thought bubble, the
// notification stack and the pet picker take input, everything else is
// click-through. The pet sits where the user drags it (position remembered per
// screen) and never wanders on the desktop; free roaming happens only in the
// screensaver mode. It reads:
//   - machine health   (omarchy-pets-health, every 10 s; 60 s when asleep)
//   - agent sessions   (hook files from omarchy-pets-agent-state + a hook-free
//                       transcript-activity fallback every 3 s)
//   - weekly limits    (the Omarchy agents widget's usage JSON)
//   - notifications    (the notification service's per-toast state files)
// Colors come from the current Omarchy theme (qs.Commons Color).
Item {
  id: root
  property var shell: null
  readonly property string home: Quickshell.env("HOME")

  // ============================================================== settings
  // ~/.config/omarchy/pets.json, hot-reloaded.
  readonly property string settingsPath: home + "/.config/omarchy/pets.json"
  property var settings: ({})
  FileView {
    id: settingsFile
    path: root.settingsPath
    blockLoading: true; watchChanges: true; printErrors: false
    // A change on disk (ours or the user's editor) triggers a real re-read;
    // parsing text() straight from onFileChanged returned the stale buffer.
    onFileChanged: settingsFile.reload()
    onLoaded: root.reloadSettings()
    onLoadFailed: root.settings = ({})
  }
  function reloadSettings() { try { settings = JSON.parse(settingsFile.text()) } catch (e) { settings = ({}) } }
  function saveSettings(patch) {
    var next = JSON.parse(JSON.stringify(settings || {}))
    for (var k in patch) next[k] = patch[k]
    settings = next
    settingsFile.setText(JSON.stringify(next, null, 2) + "\n")
  }
  readonly property string petId: settings.pet || "rocky"
  // Your own name for each pet: settings.names = { rocky: "Piedrita", ... }
  function nickname(id) { var n = settings.names || {}; return n[id] ? String(n[id]) : "" }
  function displayName(p) { return p ? (nickname(p.id) || p.name) : "" }
  readonly property string petName: displayName(pet)
  function renamePet(name) {
    if (!pet) return
    var names = JSON.parse(JSON.stringify(settings.names || {}))
    name = String(name || "").trim()
    if (name === "" || name === pet.name) delete names[pet.id]; else names[pet.id] = name
    saveSettings({ names: names })
    think(name ? "Call me " + name + "." : "Back to " + pet.name + ".", thoughtMs)
  }
  readonly property bool soundsOn: settings.sounds !== false
  readonly property real volume: settings.volume !== undefined ? Number(settings.volume) : 0.5
  readonly property real drawScale: settings.scale !== undefined ? Number(settings.scale) : 0.5
  readonly property int doneTimeoutSec: (settings.doneTimeoutMin !== undefined ? Number(settings.doneTimeoutMin) : 10) * 60
  readonly property int thoughtMs: (settings.thoughtSeconds !== undefined ? Number(settings.thoughtSeconds) : 8) * 1000
  readonly property real saverDim: settings.screensaverDim !== undefined ? Number(settings.screensaverDim) : 0.55

  // ================================================================== pets
  // Installed pets, validated by omarchy-pets-list (needs the nine rows + sheet),
  // merged with the catalog of Codex's built-in pets so the picker shows every
  // pet you can have; a click on one that is not installed downloads it first.
  readonly property var catalog: [
    { id: "codex",       name: "Codex",       description: "The original Codex companion" },
    { id: "dewey",       name: "Dewey",       description: "A tidy duck for calm workspace days" },
    { id: "fireball",    name: "Fireball",    description: "Hot path energy for fast iteration" },
    { id: "rocky",       name: "Rocky",       description: "A steady rock when the diff gets large" },
    { id: "seedy",       name: "Seedy",       description: "Small green shoots for new ideas" },
    { id: "stacky",      name: "Stacky",      description: "A balanced stack for deep work" },
    { id: "bsod",        name: "BSOD",        description: "A tiny blue-screen gremlin" },
    { id: "null-signal", name: "Null Signal", description: "Quiet signal from the void" }
  ]
  property var pets: []
  readonly property var allPets: {
    var list = pets.map(function(x) { x.installed = true; return x })
    var have = {}; list.forEach(function(x) { have[x.id] = true })
    catalog.forEach(function(c) { if (!have[c.id]) list.push({ id: c.id, name: c.name, description: c.description, installed: false, valid: false, reason: "not downloaded yet — click to fetch" }) })
    list.sort(function(a, b) { return a.name.localeCompare(b.name) })
    return list
  }
  property string installing: ""
  Process {
    id: installProc
    stdout: StdioCollector { onStreamFinished: {} }
    onExited: function(code) {
      var id = root.installing; root.installing = ""
      if (code === 0) { root.pendingSelect = id; petsScan.restart(); root.think("Got " + id + "!", root.thoughtMs) }
      else root.think("Couldn't download " + id + ".", root.thoughtMs)
    }
  }
  property string pendingSelect: ""
  function installPet(id) {
    if (installing !== "") return
    installing = id; think("Fetching " + id + "…", 0)
    installProc.command = [root.home + "/.local/bin/omarchy-pets-fetch", id]; installProc.running = true
  }
  readonly property var pet: {
    for (var i = 0; i < pets.length; i++) if (pets[i].id === petId && pets[i].valid) return pets[i]
    for (var j = 0; j < pets.length; j++) if (pets[j].valid) return pets[j]
    return null
  }
  // Double buffer: `pet` is the target, `shown` is the pet whose spritesheet is
  // fully decoded. Everything renders from `shown`, so switching never paints a
  // half-loaded or mis-clipped frame; a loading pulse covers the gap.
  property var shown: null
  readonly property bool loading: pet !== null && (shown === null || shown.id !== pet.id || shown.sheet !== pet.sheet)
  Image {
    id: preload
    visible: false
    source: root.pet ? "file://" + root.pet.sheet : ""
    asynchronous: true; cache: true
    onStatusChanged: if (status === Image.Ready && root.pet && source == "file://" + root.pet.sheet) root.shown = root.pet
  }
  readonly property string sheet: shown ? "file://" + shown.sheet : ""
  readonly property int cellW: shown ? shown.cellW : 192
  readonly property int cellH: shown ? shown.cellH : 208
  readonly property var rowIndex: {
    var m = {}; var rows = shown ? shown.rows : []
    for (var i = 0; i < rows.length; i++) m[rows[i]] = i
    return m
  }
  function frames(anim) { var f = shown && shown.frames ? shown.frames[anim] : undefined; return f ? Number(f) : 8 }
  function row(anim) { var r = rowIndex[anim]; return r === undefined ? 0 : r }
  FileView { path: root.home + "/.config/omarchy/pets/"; watchChanges: true; printErrors: false; onFileChanged: petsScan.restart() }
  Timer { id: petsScan; interval: 300; onTriggered: if (!petsProc.running) petsProc.running = true }
  Process {
    id: petsProc
    command: [root.home + "/.local/bin/omarchy-pets-list"]
    stdout: StdioCollector { onStreamFinished: root.ingestPets(this.text) }
  }
  function ingestPets(text) {
    var list = []
    String(text).split("\n").forEach(function(l) { l = l.trim(); if (!l) return; try { list.push(JSON.parse(l)) } catch (e) {} })
    list.sort(function(a, b) { return a.name.localeCompare(b.name) })
    pets = list
    if (pendingSelect !== "") { var id = pendingSelect; pendingSelect = ""; for (var i = 0; i < list.length; i++) if (list[i].id === id && list[i].valid) selectPet(id) }
  }
  function selectPet(id) { saveSettings({ pet: id }); think("Now I'm " + (nickname(id) || id) + ".", thoughtMs) }
  onShownChanged: if (shown && thought.indexOf("Now I'm") === 0) thoughtTimer.restart()

  // ================================================================ health
  property var health: ({})
  property int lastThrottle: -1
  property real hotSince: 0
  property bool tired: false
  property string tiredWhy: ""
  readonly property bool weak: health.batteryPct !== undefined && health.batteryPct >= 0
                               && health.batteryPct <= 15 && health.discharging === true
  function ingestHealth(json) {
    var h; try { h = JSON.parse(json) } catch (e) { return }
    var throttled = lastThrottle >= 0 && h.throttle > lastThrottle
    lastThrottle = h.throttle
    var hotCpu = h.cpuPct >= 85, hotTemp = h.tempC > 85, hotMem = h.memUsedPct >= 92
    var overloaded = hotCpu || hotTemp || hotMem
    var now = Date.now() / 1000
    if (overloaded) { if (!hotSince) hotSince = now } else hotSince = 0
    var wasTired = tired
    tired = throttled || (hotSince > 0 && now - hotSince >= 20)
    if (tired) {
      tiredWhy = hotMem ? "Memory at " + h.memUsedPct + "% — " + h.topMem.name + " holds " + (h.topMem.mb / 1024).toFixed(1) + " GB"
               : hotTemp ? "CPU at " + h.tempC + "°C — " + h.topCpu.name + " is burning " + h.topCpu.pct + "%"
               : throttled ? "Thermal throttling — " + h.topCpu.name + " at " + h.topCpu.pct + "%"
               : "CPU at " + h.cpuPct + "% — " + h.topCpu.name + " takes " + h.topCpu.pct + "%"
      if (!wasTired) think(tiredWhy, thoughtMs * 2)
    }
    health = h
  }
  Process {
    id: healthProc
    command: [root.home + "/.local/bin/omarchy-pets-health"]
    stdout: StdioCollector { onStreamFinished: root.ingestHealth(this.text) }
  }
  Timer {
    interval: root.asleep ? 60000 : 10000
    running: true; repeat: true; triggeredOnStart: true
    onTriggered: if (!healthProc.running) healthProc.running = true
  }

  // ================================================================ agents
  // Any number of agents. Two sources, merged per agent id:
  //   - hook files in agentsDir (omarchy-pets-agent-state): {agent, state:
  //     running|waiting|done, session, message, cwd, updatedAt}
  //   - omarchy-pets-activity: ids whose transcripts were written recently
  //     (registry in settings.agents + defaults; no id is hardcoded here)
  // Per agent the strongest state wins: waiting > running > done.
  readonly property string agentsDir: home + "/.local/state/omarchy/pets/agents/"
  readonly property string usageDir: home + "/.local/state/omarchy/agents/usage/"
  property var agents: []              // raw hook records, newest first
  property var activeAgents: []        // ids from transcript activity
  property var hungryAgents: []
  readonly property var agentStates: {
    var m = {}, rank = { waiting: 3, running: 2, done: 1 }
    agents.forEach(function(a) {
      var cur = m[a.agent]
      if (!cur || rank[a.state] > rank[cur.state]) m[a.agent] = a
    })
    activeAgents.forEach(function(id) {
      if (!m[id] || m[id].state === "done") m[id] = { agent: id, state: "running", cwd: "", message: "", session: "", updatedAt: Date.now() / 1000 }
    })
    return m
  }
  function agentsIn(state) { var out = []; for (var id in agentStates) if (agentStates[id].state === state) out.push(agentStates[id]); return out }
  readonly property var waitingAgents: agentsIn("waiting")
  readonly property var runningAgents: agentsIn("running")
  readonly property var doneAgents: agentsIn("done")
  readonly property var agentWaiting: waitingAgents.length ? waitingAgents[0] : null
  function names(list) { return list.map(function(a) { return cap(a.agent) }).join(" & ") }
  function cap(s) { s = String(s || ""); return s.charAt(0).toUpperCase() + s.slice(1) }
  function shortCwd(a) { var c = a && a.cwd ? String(a.cwd) : ""; return c ? " · " + c.split("/").filter(Boolean).pop() : "" }
  // One-line summary of every agent, for thoughts and the health bubble.
  function agentsSummary() {
    var parts = []
    if (waitingAgents.length) parts.push(names(waitingAgents) + (waitingAgents.length > 1 ? " need you" : " needs you"))
    if (runningAgents.length) parts.push(names(runningAgents) + (runningAgents.length > 1 ? " are working" : " is working"))
    if (doneAgents.length) parts.push(names(doneAgents) + (doneAgents.length > 1 ? " are done" : " is done"))
    return parts.join(" · ")
  }

  FileView { path: root.agentsDir; watchChanges: true; printErrors: false; onFileChanged: agentsScan.restart() }
  Timer { id: agentsScan; interval: 100; onTriggered: if (!agentsProc.running) agentsProc.running = true; else agentsScan.restart() }
  Process {
    id: agentsProc
    command: ["bash", "-c", "shopt -s nullglob; for f in \"$1\"/*.json; do cat \"$f\"; printf '\\x1e'; done", "--", root.agentsDir]
    stdout: StdioCollector { onStreamFinished: root.ingestAgents(this.text) }
  }
  function ingestAgents(text) {
    var list = [], now = Date.now() / 1000
    String(text).split("\x1e").forEach(function(chunk) {
      chunk = chunk.trim(); if (!chunk) return
      try {
        var a = JSON.parse(chunk), age = now - (Number(a.updatedAt) || 0)
        if (age < 6 * 3600 && !(a.state === "done" && age > root.doneTimeoutSec)) list.push(a)
      } catch (e) {}
    })
    list.sort(function(a, b) { return (Number(b.updatedAt) || 0) - (Number(a.updatedAt) || 0) })
    agents = list
  }
  Timer { interval: 60000; running: true; repeat: true; onTriggered: agentsScan.restart() }

  Process {
    id: activityProc
    command: [root.home + "/.local/bin/omarchy-pets-activity", "8"]
    stdout: StdioCollector { onStreamFinished: root.activeAgents = String(this.text).split("\n").filter(function(s) { return s.trim() !== "" }) }
  }
  Timer { interval: 3000; running: !root.asleep; repeat: true; triggeredOnStart: true; onTriggered: if (!activityProc.running) activityProc.running = true }

  // Events: a new waiting agent (sticky thought, sound), a newly done agent (timed thought, sound).
  property string waitingKey: ""
  property var doneSeen: ({})
  onAgentStatesChanged: {
    var wk = waitingAgents.map(function(a) { return a.agent + ":" + a.session + ":" + a.updatedAt }).join("|")
    if (wk !== waitingKey) {
      waitingKey = wk
      if (waitingAgents.length) {
        waving = true; waveTimer.restart(); play("attention")
        var w = waitingAgents[0]
        think(names(waitingAgents) + (waitingAgents.length > 1 ? " need you" : " needs you") + (w.message ? ": " + w.message : "") + shortCwd(w), 0)
      } else if (thoughtSticky) clearThought()
    }
    var seen = JSON.parse(JSON.stringify(doneSeen)), fresh = []
    doneAgents.forEach(function(a) { var k = a.agent + ":" + a.session + ":" + a.updatedAt; if (!seen[k]) { seen[k] = true; fresh.push(a) } })
    for (var k in seen) { var still = false; doneAgents.forEach(function(a) { if (a.agent + ":" + a.session + ":" + a.updatedAt === k) still = true }); if (!still) delete seen[k] }
    doneSeen = seen
    if (fresh.length && !waitingAgents.length) {
      play("done")
      think(names(fresh) + (fresh.length > 1 ? " are done" : " is done") + shortCwd(fresh[0]) + " — take a look." + (runningAgents.length ? " " + names(runningAgents) + (runningAgents.length > 1 ? " are" : " is") + " still working." : ""), thoughtMs * 2)
    }
  }

  FileView { path: root.usageDir; watchChanges: true; printErrors: false; onFileChanged: usageScan.restart() }
  Timer { id: usageScan; interval: 500; onTriggered: if (!usageProc.running) usageProc.running = true; else usageScan.restart() }
  Process {
    id: usageProc
    command: ["bash", "-c", "shopt -s nullglob; for f in \"$1\"/*.json; do jq -c '{id, limits: [(.limits // [])[] | {label, percent}]}' \"$f\" 2>/dev/null; done", "--", root.usageDir]
    stdout: StdioCollector { onStreamFinished: root.ingestUsage(this.text) }
  }
  function ingestUsage(text) {
    var hungry = []
    String(text).split("\n").forEach(function(line) {
      line = line.trim(); if (!line) return
      try { var u = JSON.parse(line); (u.limits || []).forEach(function(l) { if (Number(l.percent) >= 0.9) hungry.push({ id: u.id, label: l.label, percent: Number(l.percent) }) }) } catch (e) {}
    })
    hungryAgents = hungry
  }
  Timer { interval: 900000; running: true; repeat: true; triggeredOnStart: true; onTriggered: usageScan.restart() }

  // ========================================================= notifications
  // One JSON per live toast, moved to history/ by the service on expiry/dismiss.
  readonly property string notifDir: home + "/.local/state/omarchy/notifications/"
  property var notes: []
  property string lastNoteKey: ""
  property bool waving: false
  readonly property bool critical: notes.length > 0 && Number(notes[0].urgency) === 2
  FileView { path: root.notifDir; watchChanges: true; printErrors: false; onFileChanged: notifScan.restart() }
  Timer { id: notifScan; interval: 80; onTriggered: if (!notifProc.running) notifProc.running = true; else notifScan.restart() }
  Process {
    id: notifProc
    command: ["bash", "-c", "shopt -s nullglob; for f in \"$1\"/*.json; do cat \"$f\"; printf '\\x1e'; done", "--", root.notifDir]
    stdout: StdioCollector { onStreamFinished: root.ingestNotes(this.text) }
  }
  function ingestNotes(text) {
    var list = []
    String(text).split("\x1e").forEach(function(chunk) { chunk = chunk.trim(); if (!chunk) return; try { list.push(JSON.parse(chunk)) } catch (e) {} })
    list.sort(function(a, b) { return (Number(b.timestamp) || 0) - (Number(a.timestamp) || 0) })
    var key = list.length ? String(list[0].id) + ":" + String(list[0].timestamp) : ""
    if (key && key !== lastNoteKey) { lastNoteKey = key; waving = true; waveTimer.restart(); play(Number(list[0].urgency) === 2 ? "critical" : "notification") }
    if (!key) lastNoteKey = ""
    notes = list
  }
  Timer { id: waveTimer; interval: 2600; onTriggered: root.waving = false }
  Process { id: notifIpc; running: false }
  function notifCall(fn, arg) { notifIpc.command = arg !== undefined ? ["omarchy-shell", "notifications", fn, arg] : ["omarchy-shell", "notifications", fn]; notifIpc.running = true }
  function invokeNote(n, idx) {
    var argv = n && n.execArgv ? parseArgv(n.execArgv) : null
    if (argv && argv.length) { Quickshell.execDetached(argv); notifCall("dismiss", n.summary) }
    else if (idx === 0) notifCall("invokeLast")
    else notifCall("dismiss", n.summary)
  }
  function parseArgv(s) { try { var v = JSON.parse(s); return Array.isArray(v) ? v.map(String) : null } catch (e) { return String(s).split(/\s+/) } }

  // ================================================================ sounds
  property string lastSound: ""
  Process { id: soundProc; running: false }
  Timer { id: soundCooldown; interval: 1500 }
  function soundFile(kind) {
    var d = { notification: "/usr/share/sounds/freedesktop/stereo/message-new-instant.oga", critical: "/usr/share/sounds/freedesktop/stereo/dialog-warning.oga",
              attention: "/usr/share/sounds/freedesktop/stereo/window-attention.oga", done: "/usr/share/sounds/freedesktop/stereo/complete.oga" }
    var s = settings.sound || {}; return s[kind] || d[kind]
  }
  function play(kind) {
    if (!soundsOn || soundCooldown.running) return
    soundProc.command = ["pw-play", "--volume", String(volume), soundFile(kind)]; soundProc.running = true
    lastSound = kind + " " + new Date().toISOString().substr(11, 8); soundCooldown.restart()
  }

  // ============================================================== thoughts
  // What the pet is thinking: shown in a thought bubble. Sticky thoughts (ms=0)
  // stay until cleared; timed ones fade after ms.
  property string thought: ""
  property bool thoughtSticky: false
  function think(text, ms) { thought = text; thoughtSticky = ms === 0; if (ms > 0) thoughtTimer.interval = ms; thoughtTimer.running = ms > 0 }
  function clearThought() { thought = ""; thoughtSticky = false; thoughtTimer.stop() }
  Timer { id: thoughtTimer; onTriggered: root.clearThought() }
  function healthThought() {
    var h = health; if (h.tempC === undefined) return "…"
    var s = "CPU " + h.cpuPct + "% (" + h.topCpu.name + " " + h.topCpu.pct + "%) · " + h.tempC + "°C · RAM " + h.memUsedPct + "% (" + h.topMem.name + " " + (h.topMem.mb / 1024).toFixed(1) + " GB)"
    if (h.batteryPct >= 0) s += " · battery " + h.batteryPct + "%" + (h.discharging ? "" : " ⚡")
    if (hungryAgents.length) s += " · " + hungryAgents.map(function(x) { return x.id + " " + Math.round(x.percent * 100) + "% of " + x.label }).join(", ")
    var ag = agentsSummary(); if (ag) s = ag + ". " + s
    return s
  }

  // ================================================================== idle
  property bool asleep: false
  IdleMonitor { timeout: 120; respectInhibitors: true; onIsIdleChanged: root.asleep = isIdle }

  // ================================================================ cursor
  // Global cursor from Hyprland (layer surfaces only see it over the sprite).
  // One short `hyprctl cursorpos` every 250 ms, only while awake, visible and
  // not in screensaver mode. (A long-lived shell loop piped into the shell
  // stalled after a few lines; discrete runs are reliable and just as cheap.)
  property real cursorX: -1
  property real cursorY: -1
  property var debugFacing: ({})   // filled by the first screen's pet, for `pets status`
  Process {
    id: cursorProc
    command: ["hyprctl", "cursorpos"]
    stdout: StdioCollector { onStreamFinished: { var m = /(-?\d+),\s*(-?\d+)/.exec(this.text); if (m) { root.cursorX = Number(m[1]); root.cursorY = Number(m[2]) } } }
  }
  Timer { interval: 250; repeat: true; running: !root.asleep && !root.fullscreenFocused && !root.saverOn; onTriggered: if (!cursorProc.running) cursorProc.running = true }

  // ================================================================= state
  readonly property string petState: waitingAgents.length ? "needs-you" : weak ? "weak" : tired ? "tired"
                                   : runningAgents.length ? "working" : doneAgents.length ? "ready" : hungryAgents.length > 0 ? "hungry"
                                   : asleep ? "asleep" : "resting"
  readonly property bool fullscreenFocused: ToplevelManager.activeToplevel ? ToplevelManager.activeToplevel.fullscreen : false

  // ============================================================== position
  readonly property string posPath: home + "/.local/state/omarchy/pets/position.json"
  property var positions: ({})
  FileView { id: posFile; path: root.posPath; blockLoading: true; printErrors: false
    onLoaded: { try { root.positions = JSON.parse(text()) } catch (e) { root.positions = ({}) } }
    onLoadFailed: root.positions = ({}) }
  function savePosition(name, x, y) {
    var next = JSON.parse(JSON.stringify(positions || {})); next[name] = { x: Math.round(x), y: Math.round(y) }
    positions = next; posFile.setText(JSON.stringify(next))
  }

  // ============================================================ per screen
  property bool pickerOpen: false
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      visible: !root.fullscreenFocused && !root.saverOn && root.shown !== null
      WlrLayershell.namespace: "omarchy-pets"
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.keyboardFocus: picker.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }
      mask: Region { item: pet; regions: [ Region { item: stack }, Region { item: thoughtBubble }, Region { item: picker } ] }

      readonly property string screenName: modelData ? modelData.name : ""
      readonly property int screenX: modelData && modelData.x !== undefined ? modelData.x : 0
      readonly property var saved: root.positions[screenName]
      readonly property int spriteW: Math.round(root.cellW * root.drawScale)
      readonly property int spriteH: Math.round(root.cellH * root.drawScale)

      // ----------------------------------------------------------- the pet
      Item {
        id: pet
        width: win.spriteW; height: win.spriteH
        x: win.saved ? Math.min(win.saved.x, win.width - width) : win.width - width - 24
        y: win.saved ? Math.min(win.saved.y, win.height - height) : win.height - height - 24
        property int frame: 0
        readonly property bool dragging: mouse.pressed && mouse.drag.active
        readonly property real centerGX: win.screenX + x + width / 2
        readonly property int facing: root.cursorX < 0 ? 0 : root.cursorX < centerGX - width ? -1 : root.cursorX > centerGX + width ? 1 : 0
        // Facing the cursor is a plain horizontal flip of whatever the pet is
        // doing (the sheet's poses face right). The running rows already have
        // a direction, so they are picked instead of flipped while resting.
        readonly property bool mirrored: facing < 0 && anim !== "running-left" && anim !== "running-right" && root.petState !== "asleep"
        onFacingChanged: Qt.callLater(function() { root.debugFacing = { screen: win.screenName, petCenterGX: pet.centerGX, facing: pet.facing, mirrored: pet.mirrored, anim: pet.anim } })
        readonly property string anim: root.petState === "needs-you" ? (root.waving ? "jumping" : "waiting")
                                     : root.petState === "weak" || root.petState === "tired" || root.petState === "hungry" ? "failed"
                                     : root.petState === "working" ? "running"
                                     : root.petState === "ready" ? "review"
                                     : root.petState === "asleep" ? "idle"
                                     : root.critical ? "jumping"
                                     : root.waving ? "waving"
                                     : facing > 0 ? "running-right" : facing < 0 ? "running-left" : "idle"
        readonly property int shownFrame: root.petState === "asleep" ? 1
                                        : root.petState === "weak" ? root.frames("failed") - 1
                                        : root.petState === "hungry" ? (frame % 16 < 8 ? 0 : 1)
                                        : (anim === "running-right" || anim === "running-left") && root.petState === "resting" ? 0
                                        : frame % root.frames(anim)
        // The whole sheet, scaled, inside a clipping box offset to the current
        // frame. One decode per sheet; changing frame or pet never reloads the
        // file (sourceClipRect would, and paints a blank frame meanwhile).
        Item {
          anchors.fill: parent
          clip: true
          transform: Scale { origin.x: pet.width / 2; xScale: pet.mirrored ? -1 : 1 }
          Image {
            id: sheetImg
            source: root.sheet
            width: (root.shown ? root.shown.columns : 8) * pet.width
            height: (root.shown ? root.shown.rows.length : 9) * pet.height
            x: -pet.shownFrame * pet.width
            y: -root.row(pet.anim) * pet.height
            fillMode: Image.Stretch; smooth: false; mipmap: false; cache: true; asynchronous: false
          }
        }
        // Loading pulse while a new pet's sheet is being decoded.
        Rectangle {
          anchors.fill: parent; radius: 10
          color: Color.tooltip.background
          opacity: root.loading || sheetImg.status !== Image.Ready ? 0.75 : 0
          Behavior on opacity { NumberAnimation { duration: 150 } }
          Text {
            anchors.centerIn: parent
            text: "•••"; color: Color.accent; font.pixelSize: 18; font.bold: true
            SequentialAnimation on opacity { running: root.loading || sheetImg.status !== Image.Ready; loops: Animation.Infinite
              NumberAnimation { to: 0.2; duration: 350 } NumberAnimation { to: 1; duration: 350 } }
          }
        }
        Text {
          visible: root.petState === "asleep"
          text: "z"; color: Color.foreground; font.pixelSize: 16; font.bold: true
          anchors.left: parent.right; anchors.leftMargin: -14; anchors.bottom: parent.top; anchors.bottomMargin: -22
        }
        MouseArea {
          id: mouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: Qt.OpenHandCursor
          drag.target: pet; drag.axis: Drag.XAndYAxis
          drag.minimumX: 0; drag.maximumX: win.width - pet.width; drag.minimumY: 0; drag.maximumY: win.height - pet.height
          onReleased: root.savePosition(win.screenName, pet.x, pet.y)
          onClicked: function(m) {
            if (m.button === Qt.RightButton) { picker.open = !picker.open; if (picker.open) petsScan.restart() }
            else if (root.thought !== "" && !root.thoughtSticky) root.clearThought()
            else root.think(root.healthThought(), root.thoughtMs)
          }
        }
      }

      // Anchor above the pet (or below when there is no room), clamped to the screen.
      readonly property bool above: pet.y > win.height * 0.35
      function clampX(w) { return Math.max(6, Math.min(win.width - w - 6, pet.x + pet.width / 2 - w / 2)) }

      // ----------------------------------------------------- thought bubble
      Rectangle {
        id: thoughtBubble
        visible: opacity > 0
        opacity: root.thought !== "" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        radius: 8
        color: Color.tooltip.background
        border.color: root.petState === "needs-you" ? Color.urgent : Color.tooltip.border
        border.width: 1
        width: Math.min(360, thoughtText.implicitWidth + 30)
        height: thoughtText.implicitHeight + 22
        x: win.clampX(width)
        y: win.above ? (stack.visible ? stack.y - height - 10 : pet.y - height - 26) : (stack.visible ? stack.y + stack.height + 10 : pet.y + pet.height + 26)
        Text {
          id: thoughtText
          anchors.centerIn: parent
          width: Math.min(330, implicitWidth)
          text: root.thought
          color: Color.tooltip.text
          font.pixelSize: 12; font.family: Style.font.family
          wrapMode: Text.Wrap
        }
        // Thought trail: two small circles toward the pet.
        Rectangle { width: 10; height: 10; radius: 5; color: parent.color; border.color: parent.border.color; border.width: 1
          x: pet.x + pet.width / 2 - parent.x - 5; y: win.above ? parent.height + 4 : -14 }
        Rectangle { width: 6; height: 6; radius: 3; color: parent.color; border.color: parent.border.color; border.width: 1
          x: pet.x + pet.width / 2 - parent.x - 3 + (win.above ? 8 : 8); y: win.above ? parent.height + 15 : -22 }
        MouseArea { anchors.fill: parent; onClicked: if (!root.thoughtSticky) root.clearThought() }
      }

      // ------------------------------------------------ notification stack
      // Every live notification as a compact tooltip-style card (Omarchy's
      // tooltip colors), newest on top, animated in and out.
      Column {
        id: stack
        visible: root.notes.length > 0
        width: 320
        spacing: 6
        x: win.clampX(width)
        y: win.above ? pet.y - height - 12 : pet.y + pet.height + 12
        add: Transition { NumberAnimation { properties: "opacity"; from: 0; to: 1; duration: 180 } NumberAnimation { properties: "scale"; from: 0.96; to: 1; duration: 180; easing.type: Easing.OutQuad } }
        move: Transition { NumberAnimation { properties: "y"; duration: 160; easing.type: Easing.OutQuad } }

        Repeater {
          model: root.notes.slice(0, 5)
          delegate: Rectangle {
            id: card
            required property var modelData
            required property int index
            readonly property bool crit: Number(modelData.urgency) === 2
            width: stack.width
            height: cardCol.implicitHeight + 16
            radius: 6
            color: Color.tooltip.background
            border.color: crit ? Color.urgent : Color.tooltip.border
            border.width: 1
            Column {
              id: cardCol
              x: 12; y: 8; width: parent.width - 24; spacing: 1
              Row {
                spacing: 6; width: parent.width
                Text { text: modelData.glyph || ""; color: card.crit ? Color.urgent : Color.accent; font.pixelSize: 12; font.family: Style.font.family; visible: text !== "" }
                Text { text: modelData.summary || ""; color: Color.tooltip.text; font.pixelSize: 12; font.bold: true; font.family: Style.font.family; elide: Text.ElideRight; width: parent.width - (appTag.visible ? appTag.width + 6 : 0) - 20 }
                Text { id: appTag; text: modelData.app || ""; color: Color.muted; font.pixelSize: 10; font.family: Style.font.family; visible: text !== "" && text !== (modelData.summary || "") }
              }
              Text { text: modelData.body || ""; color: Color.tooltip.text; opacity: 0.8; font.pixelSize: 11; font.family: Style.font.family; wrapMode: Text.Wrap; width: parent.width; maximumLineCount: 2; elide: Text.ElideRight; visible: text !== "" }
            }
            MouseArea {
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              cursorShape: Qt.PointingHandCursor
              onClicked: function(m) { if (m.button === Qt.RightButton) root.notifCall("dismiss", card.modelData.summary); else root.invokeNote(card.modelData, card.index) }
            }
          }
        }
        Text {
          visible: root.notes.length > 5
          text: "+" + (root.notes.length - 5) + " more"
          color: Color.muted; font.pixelSize: 10; font.family: Style.font.family
        }
      }

      // ------------------------------------------------------- pet picker
      // Right-click the pet: choose among installed pets. Invalid ones (missing
      // sheet or rows) are listed greyed out with the reason.
      Rectangle {
        id: picker
        property bool open: root.pickerOpen
        onOpenChanged: root.pickerOpen = open
        visible: opacity > 0
        opacity: open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
        radius: 8
        color: Color.tooltip.background
        border.color: Color.tooltip.border
        border.width: 1
        width: 300
        height: pickCol.implicitHeight + 24
        x: Math.max(6, Math.min(win.width - width - 6, pet.x + pet.width + 12 + width <= win.width ? pet.x + pet.width + 12 : pet.x - width - 12))
        y: Math.max(6, Math.min(win.height - height - 6, pet.y + pet.height / 2 - height / 2))
        Timer { interval: 20000; running: picker.open && root.installing === ""; onTriggered: picker.open = false }
        Column {
          id: pickCol
          x: 12; y: 12; width: parent.width - 24; spacing: 4
          Text { text: "Pets"; color: Color.muted; font.pixelSize: 11; font.family: Style.font.family; font.letterSpacing: 1 }
          // Name field for the current pet: type a nickname, Enter to save, empty = original name.
          Rectangle {
            width: pickCol.width; height: 30; radius: 6
            color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, nameInput.activeFocus ? 0.18 : 0.08)
            border.color: nameInput.activeFocus ? Color.accent : Color.tooltip.border; border.width: 1
            Row {
              anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 8
              Text { anchors.verticalCenter: parent.verticalCenter; text: "Name"; color: Color.muted; font.pixelSize: 11; font.family: Style.font.family }
              TextInput {
                id: nameInput
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 60
                color: Color.tooltip.text; font.pixelSize: 13; font.family: Style.font.family
                selectByMouse: true; clip: true
                text: root.petName
                onAccepted: { root.renamePet(text); picker.open = false }
                Keys.onEscapePressed: { text = root.petName; focus = false }
                Text { anchors.fill: parent; text: "type a name, Enter to save"; color: Color.muted; font.pixelSize: 12; font.family: Style.font.family; visible: nameInput.text === "" && !nameInput.activeFocus }
              }
            }
            Connections { target: picker; function onOpenChanged() { if (picker.open) nameInput.text = root.petName } }
          }
          Repeater {
            model: root.allPets
            delegate: Rectangle {
              required property var modelData
              width: pickCol.width; height: 44; radius: 8
              readonly property bool current: root.pet && modelData.id === root.pet.id
              readonly property bool clickable: modelData.valid || !modelData.installed
              color: rowMouse.containsMouse && clickable ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18) : "transparent"
              opacity: clickable ? 1 : 0.45
              Row {
                anchors.verticalCenter: parent.verticalCenter; x: 8; spacing: 10
                Image {
                  width: 30; height: 32; visible: modelData.valid
                  source: picker.open && modelData.valid ? "file://" + modelData.sheet : ""
                  sourceClipRect: Qt.rect(0, 0, modelData.cellW, modelData.cellH); fillMode: Image.Stretch; smooth: false; asynchronous: true
                }
                Rectangle { width: 30; height: 32; radius: 6; visible: !modelData.valid; color: "transparent"; border.color: Color.muted; border.width: 1
                  Text { anchors.centerIn: parent; text: root.installing === modelData.id ? "…" : (modelData.installed ? "!" : "↓"); color: Color.muted; font.pixelSize: 14 } }
                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  Text { text: (root.nickname(modelData.id) ? root.nickname(modelData.id) + "  · " + modelData.name : modelData.name) + (current ? "  ✓" : ""); color: Color.tooltip.text; font.pixelSize: 13; font.bold: current; font.family: Style.font.family }
                  Text { text: root.installing === modelData.id ? "downloading…" : (modelData.valid ? modelData.description : modelData.reason); color: Color.muted; font.pixelSize: 11; font.family: Style.font.family; width: pickCol.width - 70; elide: Text.ElideRight }
                }
              }
              MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true; enabled: clickable; cursorShape: Qt.PointingHandCursor
                onClicked: { if (modelData.valid) { root.selectPet(modelData.id); picker.open = false } else root.installPet(modelData.id) } }
            }
          }
          Text { text: "↓ not downloaded yet · click to fetch and switch · community pets: omarchy-pets-fetch <id> <folder>"; color: Color.muted; font.pixelSize: 10; font.family: Style.font.family; width: pickCol.width; wrapMode: Text.Wrap }
        }
      }

      // Idle animation clock: 8 fps only when something animates, 4 fps at rest, off asleep.
      Timer {
        interval: root.petState === "resting" ? 250 : 125
        repeat: true
        running: win.visible && root.petState !== "asleep"
        onTriggered: pet.frame++
      }
    }
  }

  // =========================================================== screensaver
  // Dimmed, blurred (Hyprland layer rule) overlay where the pet roams freely.
  property bool saverOn: false
  Variants {
    model: Quickshell.screens
    PanelWindow {
      id: saver
      required property var modelData
      screen: modelData
      visible: root.saverOn && root.shown !== null
      WlrLayershell.namespace: "omarchy-pets-screensaver"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      color: Qt.rgba(0, 0, 0, root.saverDim)
      anchors { top: true; bottom: true; left: true; right: true }
      mask: Region {}
      readonly property int floorY: height - root.cellH - Math.round(height * 0.06)
      Item {
        id: walker
        width: root.cellW; height: root.cellH
        x: Math.round(saver.width * 0.3); y: saver.floorY
        property int dir: 1
        property string mode: "walk"
        property int ticks: 60
        property int frame: 0
        readonly property string anim: mode === "walk" ? (dir > 0 ? "running-right" : "running-left") : "idle"
        readonly property int shownFrame: mode === "nap" ? 1 : frame % root.frames(anim)
        Item { anchors.fill: parent; clip: true
          Image { source: saver.visible ? root.sheet : ""; width: (root.shown ? root.shown.columns : 8) * walker.width; height: (root.shown ? root.shown.rows.length : 9) * walker.height
            x: -walker.shownFrame * walker.width; y: -root.row(walker.anim) * walker.height; fillMode: Image.Stretch; smooth: false; mipmap: false; cache: true; asynchronous: false } }
        Text { visible: walker.mode === "nap"; text: "z"; color: Color.foreground; font.pixelSize: 30; font.bold: true
          anchors.left: parent.right; anchors.leftMargin: -28; anchors.bottom: parent.top; anchors.bottomMargin: -44; opacity: (walker.frame % 16) < 8 ? 1 : 0.35 }
      }
      Timer {
        interval: 125; repeat: true; running: saver.visible
        onTriggered: {
          walker.frame++; walker.ticks--
          if (walker.ticks <= 0) {
            var r = Math.random()
            if (walker.mode === "walk") { if (r < 0.25) { walker.mode = "nap"; walker.ticks = 160 + Math.floor(Math.random() * 240) } else { walker.mode = "pause"; walker.ticks = 16 + Math.floor(Math.random() * 40) } }
            else { walker.mode = "walk"; walker.ticks = 60 + Math.floor(Math.random() * 200); if (r < 0.5) walker.dir = -walker.dir; walker.y = saver.floorY - Math.round(Math.random() * saver.height * 0.5) }
            walker.frame = 0
          }
          if (walker.mode === "walk") { var nx = walker.x + walker.dir * 6; if (nx < 10) { nx = 10; walker.dir = 1 } else if (nx > saver.width - walker.width - 10) { nx = saver.width - walker.width - 10; walker.dir = -1 }; walker.x = nx }
        }
      }
    }
  }

  Component.onCompleted: { petsScan.restart(); notifScan.restart(); agentsScan.restart() }

  IpcHandler {
    target: "pets"
    function status(): string { return JSON.stringify({ pet: root.pet ? root.pet.id : null, shown: root.shown ? root.shown.id : null, loading: root.loading, name: root.petName, state: root.petState, thought: root.thought, asleep: root.asleep, tired: root.tired, weak: root.weak, cursorX: root.cursorX, facing: root.debugFacing, notes: root.notes.length, agents: root.agentStates, active: root.activeAgents, hungry: root.hungryAgents, sounds: root.soundsOn, lastSound: root.lastSound, positions: root.positions, health: root.health }) }
    function listPets(): string { return JSON.stringify(root.allPets) }
    function setPet(id: string): string { root.selectPet(id); return id }
    function installPet(id: string): string { root.installPet(id); return id }
    function rename(name: string): string { root.renamePet(name); return root.petName }
    function picker(): string { root.pickerOpen = !root.pickerOpen; if (root.pickerOpen) petsScan.restart(); return root.pickerOpen ? "open" : "closed" }
    function think(text: string): string { root.think(text, root.thoughtMs); return "ok" }
    function screensaverOn(): string { root.saverOn = true; return "on" }
    function screensaverOff(): string { root.saverOn = false; return "off" }
    function screensaverToggle(): string { root.saverOn = !root.saverOn; return root.saverOn ? "on" : "off" }
  }
}
