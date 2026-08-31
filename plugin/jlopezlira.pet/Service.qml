import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Omarchy Pet — phase 1: Rocky sits where the user puts him (drag to place;
// position remembered per screen), reacts to machine health, sleeps when the
// session is idle, and shows a health bubble on click. He never wanders on the
// desktop — free roaming is reserved for the screensaver mode. Everything
// outside the sprite is click-through.
Item {
  id: root
  property var shell: null

  // ---------------------------------------------------------------- asset
  readonly property string home: Quickshell.env("HOME")
  readonly property string sheet: "file://" + home + "/.config/omarchy/pets/rocky/spritesheet.webp"
  readonly property int cellW: 192
  readonly property int cellH: 208
  readonly property var rows: ({ "idle": 0, "running-right": 1, "running-left": 2, "waving": 3, "jumping": 4, "failed": 5, "waiting": 6, "running": 7, "review": 8 })
  readonly property var frames: ({ "idle": 6, "running-right": 8, "running-left": 8, "waving": 4, "jumping": 5, "failed": 8, "waiting": 6, "running": 6, "review": 6 })

  // --------------------------------------------------------------- health
  property var health: ({})
  property int lastThrottle: -1
  property real hotSince: 0
  property bool tired: false
  readonly property bool weak: health.batteryPct !== undefined && health.batteryPct >= 0
                               && health.batteryPct <= 15 && health.discharging === true

  function ingestHealth(json) {
    var h
    try { h = JSON.parse(json) } catch (e) { return }
    var throttled = lastThrottle >= 0 && h.throttle > lastThrottle
    lastThrottle = h.throttle
    var overloaded = h.tempC > 85 || h.loadPerCore > 1.0
    var now = Date.now() / 1000
    if (overloaded) { if (!hotSince) hotSince = now } else hotSince = 0
    tired = throttled || (hotSince > 0 && now - hotSince >= 60)
    health = h
  }

  Process {
    id: healthProc
    command: [root.home + "/.local/bin/pet-health"]
    stdout: StdioCollector { onStreamFinished: root.ingestHealth(this.text) }
  }
  Timer {
    interval: root.asleep ? 60000 : 10000
    running: true; repeat: true; triggeredOnStart: true
    onTriggered: if (!healthProc.running) healthProc.running = true
  }

  // ------------------------------------------------------------ settings
  // ~/.config/omarchy/pet.json: sounds (bool), volume (0-1), scale, doneTimeoutMin,
  // sound.{notification,critical,attention,done} (file paths).
  readonly property string settingsPath: home + "/.config/omarchy/pet.json"
  property var settings: ({})
  FileView {
    id: settingsFile
    path: root.settingsPath
    blockLoading: true
    watchChanges: true
    printErrors: false
    onLoaded: root.reloadSettings()
    onFileChanged: root.reloadSettings()
    onLoadFailed: root.settings = ({})
  }
  function reloadSettings() { try { settings = JSON.parse(settingsFile.text()) } catch (e) { settings = ({}) } }
  readonly property bool soundsOn: settings.sounds !== false
  readonly property real volume: settings.volume !== undefined ? Number(settings.volume) : 0.5
  readonly property real drawScale: settings.scale !== undefined ? Number(settings.scale) : 0.5
  readonly property int doneTimeoutSec: (settings.doneTimeoutMin !== undefined ? Number(settings.doneTimeoutMin) : 10) * 60
  function soundFile(kind) {
    var defaults = { notification: "/usr/share/sounds/freedesktop/stereo/message-new-instant.oga",
                     critical: "/usr/share/sounds/freedesktop/stereo/dialog-warning.oga",
                     attention: "/usr/share/sounds/freedesktop/stereo/window-attention.oga",
                     done: "/usr/share/sounds/freedesktop/stereo/complete.oga" }
    var s = settings.sound || {}
    return s[kind] || defaults[kind]
  }
  // One short sound per event, with a cooldown so a hook + its own desktop
  // notification (Claude sends both) never ring twice.
  property string lastSound: ""
  Process { id: soundProc; running: false }
  Timer { id: soundCooldown; interval: 1500 }
  function play(kind) {
    if (!soundsOn || soundCooldown.running) return
    var f = soundFile(kind); if (!f) return
    soundProc.command = ["pw-play", "--volume", String(volume), f]
    soundProc.running = true
    lastSound = kind + " " + new Date().toISOString().substr(11, 8)
    soundCooldown.restart()
  }

  // ------------------------------------------------------------ position
  // {"<screen name>": {"x": px, "y": px}} — survives shell restarts and reboots.
  readonly property string posPath: home + "/.local/state/omarchy/pet/position.json"
  property var positions: ({})
  FileView {
    id: posFile
    path: root.posPath
    blockLoading: true
    printErrors: true
    onLoaded: { try { root.positions = JSON.parse(text()) } catch (e) { root.positions = ({}) } }
    onLoadFailed: root.positions = ({})
  }
  function savePosition(name, x, y) {
    var next = JSON.parse(JSON.stringify(positions || {}))
    next[name] = { x: Math.round(x), y: Math.round(y) }
    positions = next
    posFile.setText(JSON.stringify(next))
  }

  // --------------------------------------------------------------- cursor
  // Layer surfaces only see the pointer over the sprite, so the global cursor
  // comes from Hyprland. One long-lived poller (5 Hz), paused while asleep or
  // hidden. Rocky turns to face the cursor: right, left, or front when near.
  property real cursorX: -1
  property real cursorY: -1
  Process {
    id: cursorProc
    command: ["bash", "-c", "while :; do hyprctl cursorpos; sleep 0.2; done"]
    running: !root.asleep && !root.fullscreenFocused
    stdout: SplitParser {
      onRead: function(line) {
        var m = /^\s*(-?\d+),\s*(-?\d+)/.exec(line)
        if (m) { root.cursorX = Number(m[1]); root.cursorY = Number(m[2]) }
      }
    }
  }

  // -------------------------------------------------------- notifications
  // The (cloned) notification service keeps one JSON file per live toast in
  // notifDir and moves it to history/ when it expires or is dismissed. Rocky
  // only watches that folder: no D-Bus, no duplicated lifecycle.
  readonly property string notifDir: home + "/.local/state/omarchy/notifications/"
  property var notes: []
  property string lastNoteKey: ""
  property bool waving: false
  readonly property var note: notes.length > 0 ? notes[0] : null
  readonly property bool critical: note !== null && Number(note.urgency) === 2

  FileView { id: notifWatch; path: root.notifDir; watchChanges: true; printErrors: false; onFileChanged: notifScan.restart() }
  Timer { id: notifScan; interval: 80; onTriggered: if (!notifProc.running) notifProc.running = true; else notifScan.restart() }
  Process {
    id: notifProc
    command: ["bash", "-c", "shopt -s nullglob; for f in \"$1\"/*.json; do cat \"$f\"; printf '\\x1e'; done", "--", root.notifDir]
    stdout: StdioCollector { onStreamFinished: root.ingestNotes(this.text) }
  }
  function ingestNotes(text) {
    var list = []
    String(text).split("\x1e").forEach(function(chunk) {
      chunk = chunk.trim(); if (!chunk) return
      try { list.push(JSON.parse(chunk)) } catch (e) {}
    })
    list.sort(function(a, b) { return (Number(b.timestamp) || 0) - (Number(a.timestamp) || 0) })
    var key = list.length ? String(list[0].id) + ":" + String(list[0].timestamp) : ""
    if (key && key !== lastNoteKey) {
      lastNoteKey = key; waving = true; waveTimer.restart()
      play(Number(list[0].urgency) === 2 ? "critical" : "notification")
    }
    if (!key) lastNoteKey = ""
    notes = list
  }
  Timer { id: waveTimer; interval: 2600; onTriggered: root.waving = false }
  Process { id: notifIpc; running: false }
  function notifCall(fn) { notifIpc.command = ["omarchy-shell", "notifications", fn]; notifIpc.running = true }
  Component.onCompleted: notifScan.restart()

  // --------------------------------------------------------------- agents
  // One JSON per agent session in agentsDir, written by pet-agent-state from
  // the Claude Code / Codex hooks: {agent, state: running|waiting|done, session,
  // message, updatedAt}. Stale files (>6 h) are ignored. Weekly limits come from
  // the usage JSON the agents bar widget already maintains.
  readonly property string agentsDir: home + "/.local/state/omarchy/pet/agents/"
  readonly property string usageDir: home + "/.local/state/omarchy/agents/usage/"
  property var agents: []
  property var hungryAgents: []
  readonly property var agentWaiting: firstAgent("waiting")
  readonly property var agentRunning: firstAgent("running")
  readonly property var agentDone: firstAgent("done")
  onAgentWaitingChanged: if (agentWaiting) { waving = true; waveTimer.restart(); play("attention") }
  property string lastDoneKey: ""
  onAgentDoneChanged: {
    var key = agentDone ? agentDone.agent + ":" + agentDone.session + ":" + agentDone.updatedAt : ""
    if (key && key !== lastDoneKey && !agentWaiting && !agentRunning) play("done")
    lastDoneKey = key
  }
  function firstAgent(state) {
    for (var i = 0; i < agents.length; i++) if (agents[i].state === state) return agents[i]
    return null
  }
  FileView { id: agentsWatch; path: root.agentsDir; watchChanges: true; printErrors: false; onFileChanged: agentsScan.restart() }
  Timer { id: agentsScan; interval: 120; onTriggered: if (!agentsProc.running) agentsProc.running = true; else agentsScan.restart() }
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
  // "done" fades to nothing after 10 minutes; a periodic rescan re-applies the age filter.
  Timer { interval: 60000; running: true; repeat: true; onTriggered: agentsScan.restart() }

  FileView { id: usageWatch; path: root.usageDir; watchChanges: true; printErrors: false; onFileChanged: usageScan.restart() }
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
      try {
        var u = JSON.parse(line)
        ;(u.limits || []).forEach(function(l) { if (Number(l.percent) >= 0.9) hungry.push({ id: u.id, label: l.label, percent: Number(l.percent) }) })
      } catch (e) {}
    })
    hungryAgents = hungry
  }
  Timer { interval: 900000; running: true; repeat: true; triggeredOnStart: true; onTriggered: usageScan.restart() }

  // ----------------------------------------------------------------- idle
  property bool asleep: false
  IdleMonitor { timeout: 120; respectInhibitors: true; onIsIdleChanged: root.asleep = isIdle }

  // ---------------------------------------------------------------- state
  // Priority: needs you > weak > tired > working > ready > hungry > resting > asleep.
  // (Asleep is lowest: if an agent is working while you are away, that is what
  // you want to see when you come back.)
  readonly property string petState: agentWaiting ? "needs-you"
                                   : weak ? "weak"
                                   : tired ? "tired"
                                   : agentRunning ? "working"
                                   : agentDone ? "ready"
                                   : hungryAgents.length > 0 ? "hungry"
                                   : asleep ? "asleep"
                                   : "resting"
  readonly property bool fullscreenFocused: ToplevelManager.activeToplevel ? ToplevelManager.activeToplevel.fullscreen : false

  function healthSummary() {
    var h = health
    if (h.tempC === undefined) return "Rocky"
    var parts = ["CPU " + h.tempC + "°C", "load " + Math.round(h.loadPerCore * 100) + "%", "RAM free " + h.memAvailPct + "%"]
    if (h.batteryPct >= 0) parts.push("battery " + h.batteryPct + "%" + (h.discharging ? "" : " ⚡"))
    var why = petState === "weak" ? "Battery low. " : petState === "tired" ? "Tired: sustained load or heat. " : petState === "asleep" ? "Zzz. " : ""
    if (agentWaiting) why = agentWaiting.agent + " needs you" + (agentWaiting.message ? ": " + agentWaiting.message : "") + ". "
    else if (agentRunning) why = agentRunning.agent + " is working. "
    else if (agentDone) why = agentDone.agent + " is done, review it. "
    if (hungryAgents.length) why += hungryAgents.map(function(h) { return h.id + " at " + Math.round(h.percent * 100) + "% of " + h.label }).join(", ") + ". "
    return why + parts.join(" · ")
  }

  // ------------------------------------------------------------- per screen
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      visible: !root.fullscreenFocused && !root.saverOn

      WlrLayershell.namespace: "omarchy-pet"
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }

      // Only the sprite takes input; the rest of the layer is click-through.
      mask: Region { item: pet; Region { item: noteBubble } }

      readonly property int spriteW: Math.round(root.cellW * root.drawScale)
      readonly property int spriteH: Math.round(root.cellH * root.drawScale)
      readonly property string screenName: modelData ? modelData.name : ""
      readonly property var saved: root.positions[screenName]

      Item {
        id: pet
        width: win.spriteW
        height: win.spriteH
        // Default: bottom-right corner, out of the way. Otherwise where the user left him.
        x: win.saved ? Math.min(win.saved.x, win.width - width) : win.width - width - 24
        y: win.saved ? Math.min(win.saved.y, win.height - height) : win.height - height - 24

        property int frame: 0
        readonly property bool dragging: mouse.pressed

        // Where the cursor is relative to Rocky, in global coordinates.
        // -1 left, 1 right, 0 near/over him (dead zone = his own width).
        readonly property real centerGX: (win.modelData ? win.modelData.x : 0) + x + width / 2
        readonly property int facing: root.cursorX < 0 ? 0
                                    : root.cursorX < centerGX - width ? -1
                                    : root.cursorX > centerGX + width ? 1 : 0

        readonly property string anim: root.petState === "needs-you" ? (root.waving ? "jumping" : "waiting")
                                     : root.petState === "weak" || root.petState === "tired" ? "failed"
                                     : root.petState === "working" ? "running"
                                     : root.petState === "ready" ? "review"
                                     : root.petState === "hungry" ? "failed"
                                     : root.petState === "asleep" ? "idle"
                                     : (root.note !== null && root.critical) ? "jumping"
                                     : root.waving ? "waving"
                                     : (root.petState === "resting" && facing > 0) ? "running-right"
                                     : (root.petState === "resting" && facing < 0) ? "running-left"
                                     : "idle"
        readonly property int row: root.rows[anim]
        readonly property int shownFrame: root.petState === "asleep" ? 1          // idle frame 1: eyes closed
                                        : root.petState === "weak" ? 7            // failed, last frame
                                        : root.petState === "hungry" ? (frame % 16 < 8 ? 0 : 1)   // slow, sagging
                                        : (anim === "running-right" || anim === "running-left") ? 0   // standing, facing the cursor
                                        : frame % root.frames[anim]

        Image {
          id: img
          anchors.fill: parent
          source: root.sheet
          sourceClipRect: Qt.rect(pet.shownFrame * root.cellW, pet.row * root.cellH, root.cellW, root.cellH)
          fillMode: Image.Stretch
          smooth: false
          mipmap: false
          cache: true
        }

        // Sleep marker: one quiet "z", no timer behind it.
        Text {
          visible: root.petState === "asleep"
          text: "z"
          color: "#e8e0d0"
          font.pixelSize: 16
          font.bold: true
          anchors.left: parent.right
          anchors.leftMargin: -14
          anchors.bottom: parent.top
          anchors.bottomMargin: -22
        }

        MouseArea {
          id: mouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.OpenHandCursor
          drag.target: pet
          drag.axis: Drag.XAndYAxis
          drag.minimumX: 0
          drag.maximumX: win.width - pet.width
          drag.minimumY: 0
          drag.maximumY: win.height - pet.height
          onReleased: root.savePosition(win.screenName, pet.x, pet.y)
          onClicked: bubble.pop()
        }
      }

      // Notification bubble: the newest live toast, delivered by Rocky.
      // Left click = run its action (like clicking the toast), right click = dismiss.
      Rectangle {
        id: noteBubble
        visible: opacity > 0
        opacity: root.note !== null ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        readonly property bool above: pet.y - height - 12 >= 0
        radius: 10
        color: "#f4f1ea"
        border.color: root.critical ? "#b64a33" : "#2b2620"
        border.width: 2
        width: Math.min(380, noteCol.implicitWidth + 28)
        height: noteCol.implicitHeight + 22
        x: Math.max(6, Math.min(win.width - width - 6, pet.x + pet.width / 2 - width / 2))
        y: above ? pet.y - height - 12 : pet.y + pet.height + 12

        // Tail pointing at Rocky.
        Rectangle {
          width: 12; height: 12; rotation: 45
          color: parent.color; border.color: parent.border.color; border.width: 2
          x: Math.max(10, Math.min(parent.width - 22, pet.x + pet.width / 2 - parent.x - 6))
          y: parent.above ? parent.height - 7 : -5
        }
        Rectangle { anchors.fill: parent; anchors.margins: 2; radius: 8; color: parent.color }

        Column {
          id: noteCol
          anchors.centerIn: parent
          width: Math.min(352, Math.max(noteTitle.implicitWidth, noteBody.implicitWidth, noteApp.implicitWidth))
          spacing: 3
          Text { id: noteApp; text: root.note ? ((root.note.glyph ? root.note.glyph + "  " : "") + (root.note.app || "")) : ""; color: "#6b6a66"; font.pixelSize: 11; font.family: "IBM Plex Mono"; visible: text !== "" }
          Text { id: noteTitle; text: root.note ? (root.note.summary || "") : ""; color: "#1b1a19"; font.pixelSize: 14; font.bold: true; wrapMode: Text.Wrap; width: parent.width }
          Text { id: noteBody; text: root.note ? (root.note.body || "") : ""; color: "#3a3936"; font.pixelSize: 13; wrapMode: Text.Wrap; width: parent.width; visible: text !== "" }
          Text { text: root.notes.length > 1 ? "+" + (root.notes.length - 1) + " more" : ""; color: "#8a877f"; font.pixelSize: 11; visible: text !== "" }
        }
        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: Qt.PointingHandCursor
          onClicked: function(m) { root.notifCall(m.button === Qt.RightButton ? "dismissOne" : "invokeLast") }
        }
      }

      // Health bubble (phase 1), on click.
      Rectangle {
        id: bubble
        visible: opacity > 0
        opacity: 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        radius: 10
        color: "#f4f1ea"
        border.color: "#2b2620"
        border.width: 2
        width: Math.min(380, bubbleText.implicitWidth + 28)
        height: bubbleText.implicitHeight + 16
        x: Math.max(6, Math.min(win.width - width - 6, pet.x + pet.width / 2 - width / 2))
        y: noteBubble.visible ? noteBubble.y - height - 8 : pet.y - height - 10
        function pop() { bubbleText.text = root.healthSummary(); opacity = 1; bubbleTimer.restart() }
        Rectangle {
          visible: !noteBubble.visible
          width: 12; height: 12; rotation: 45
          color: parent.color; border.color: parent.border.color; border.width: 2
          x: Math.max(10, Math.min(parent.width - 22, pet.x + pet.width / 2 - parent.x - 6))
          y: parent.height - 7
        }
        Rectangle { anchors.fill: parent; anchors.margins: 2; radius: 8; color: parent.color }
        Text {
          id: bubbleText
          anchors.centerIn: parent
          color: "#1b1a19"
          font.pixelSize: 13
          font.family: "IBM Plex Sans"
          wrapMode: Text.Wrap
          width: Math.min(352, implicitWidth)
        }
        Timer { id: bubbleTimer; interval: 5000; onTriggered: bubble.opacity = 0 }
      }

      // Calm idle animation, 4 fps. Stops entirely while asleep (zero CPU).
      Timer {
        interval: 250
        repeat: true
        running: win.visible && root.petState !== "asleep"
        onTriggered: pet.frame++
      }
    }
  }

  // ---------------------------------------------------------- screensaver
  // Turned on/off by the ttfx wrapper that Omarchy's screensaver launches:
  // black Overlay layer on every screen, Rocky strolls, pauses and naps across
  // the whole width. Fully click-through so the screensaver terminal keeps
  // receiving the input that ends it.
  property bool saverOn: false

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: saver
      required property var modelData
      screen: modelData
      visible: root.saverOn
      WlrLayershell.namespace: "omarchy-pet-screensaver"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      color: "black"
      anchors { top: true; bottom: true; left: true; right: true }
      mask: Region {}

      readonly property int sw: root.cellW
      readonly property int sh: root.cellH
      readonly property int floorY: height - sh - Math.round(height * 0.06)

      Item {
        id: walker
        width: saver.sw; height: saver.sh
        x: Math.round(saver.width * 0.3); y: saver.floorY
        property int dir: 1
        property string mode: "walk"      // walk | pause | nap
        property int ticks: 60
        property int frame: 0
        readonly property string anim: mode === "walk" ? (dir > 0 ? "running-right" : "running-left") : "idle"
        readonly property int shownFrame: mode === "nap" ? 1 : frame % root.frames[anim]
        Image {
          anchors.fill: parent
          source: root.sheet
          sourceClipRect: Qt.rect(walker.shownFrame * root.cellW, root.rows[walker.anim] * root.cellH, root.cellW, root.cellH)
          fillMode: Image.Stretch; smooth: false; mipmap: false; cache: true
        }
        Text {
          visible: walker.mode === "nap"
          text: "z"; color: "#e8e0d0"; font.pixelSize: 30; font.bold: true
          anchors.left: parent.right; anchors.leftMargin: -28
          anchors.bottom: parent.top; anchors.bottomMargin: -44
          opacity: (walker.frame % 16) < 8 ? 1 : 0.35
        }
      }

      Timer {
        interval: 125
        repeat: true
        running: saver.visible
        onTriggered: {
          walker.frame++
          walker.ticks--
          if (walker.ticks <= 0) {
            var r = Math.random()
            if (walker.mode === "walk") {
              if (r < 0.25) { walker.mode = "nap";   walker.ticks = 160 + Math.floor(Math.random() * 240) }   // 20-50 s
              else          { walker.mode = "pause"; walker.ticks = 16 + Math.floor(Math.random() * 40) }
            } else {
              walker.mode = "walk"; walker.ticks = 60 + Math.floor(Math.random() * 200)
              if (r < 0.5) walker.dir = -walker.dir
              // OLED: never nap twice on the same line.
              walker.y = saver.floorY - Math.round(Math.random() * saver.height * 0.5)
            }
            walker.frame = 0
          }
          if (walker.mode === "walk") {
            var nx = walker.x + walker.dir * 6
            if (nx < 10) { nx = 10; walker.dir = 1 }
            else if (nx > saver.width - walker.width - 10) { nx = saver.width - walker.width - 10; walker.dir = -1 }
            walker.x = nx
          }
        }
      }
    }
  }

  IpcHandler {
    target: "pet"
    function screensaverOn(): string { root.saverOn = true; return "on" }
    function screensaverOff(): string { root.saverOn = false; return "off" }
    function screensaverToggle(): string { root.saverOn = !root.saverOn; return root.saverOn ? "on" : "off" }
    function status(): string { return JSON.stringify({ state: root.petState, sounds: root.soundsOn, volume: root.volume, lastSound: root.lastSound, asleep: root.asleep, tired: root.tired, weak: root.weak, notes: root.notes.length, agents: root.agents, hungry: root.hungryAgents, positions: root.positions, health: root.health }) }
  }
}
