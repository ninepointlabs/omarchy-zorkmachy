import QtQuick
import Quickshell
import Quickshell.Io
import "Games.js" as Games

// Zorkmachy's state layer, one per shell: which Zork is up, each game's
// transcript and status, and the dfrotz interpreter that actually plays it.
//
// dfrotz runs as a child process with its file access jailed to the plugin's
// state directory (-R). After every move the service quietly issues the
// game's own `save`, and when a game is opened again it issues `restore`, so
// a session can be picked up after a shell restart or a reboot without the
// player ever seeing a save prompt. Transcripts and status live in
// ~/.local/state/omarchy-zorkmachy/state.json; the Quetzal saves sit beside
// it as <game>.qzl.
Item {
  id: root

  property var shell: null
  property var settings: ({})
  property bool active: true

  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")).replace(/\/$/, "")
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy-zorkmachy"
  readonly property string statePath: stateDir + "/state.json"
  readonly property string interpreter: "/usr/bin/dfrotz"

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  // ---- state -------------------------------------------------------------
  property var games: ({})        // key -> { started, room, score, moves, transcript, updatedAt }
  property string current: ""     // game shown in the panel ("" = the picker)
  property bool loaded: false
  property bool dirReady: false
  property bool pendingSave: false
  property int revision: 0
  property bool interpreterAvailable: false
  property bool interpreterProbed: false

  // ---- interpreter -------------------------------------------------------
  // off | booting | restoring | restoreName | idle | command | saving |
  // saveName | dead
  property string phase: "off"
  property string runningKey: ""
  property string pendingLaunch: ""
  property string buffer: ""
  property string bootText: ""
  property string error: ""

  readonly property bool running: proc.running && runningKey !== ""
  readonly property bool ready: phase === "idle" && runningKey === current && current !== ""
  readonly property bool busy: running && phase !== "idle" && phase !== "dead"
  readonly property var currentGame: current !== "" && games[current] ? games[current] : null
  readonly property var currentMeta: Games.gameByKey(current)

  function gameState(key) {
    if (!games[key]) games[key] = Games.freshGame()
    return games[key]
  }

  // ---- persistence -------------------------------------------------------

  Process {
    id: mkdir
    command: ["mkdir", "-p", root.stateDir]
    running: false
    onExited: function(code) {
      root.dirReady = true
      stateFile.reload()
    }
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyState(text())
    onLoadFailed: function(error) { root.applyState("") }
    onSaveFailed: function(error) { console.warn("zorkmachy: state save failed: " + error) }
  }

  // Present or not: that is all we need to know about the interpreter.
  FileView {
    id: interpreterProbe
    path: root.interpreter
    watchChanges: false
    printErrors: false
    onLoaded: { root.interpreterAvailable = true; root.interpreterProbed = true }
    onLoadFailed: function(error) { root.interpreterAvailable = false; root.interpreterProbed = true }
  }

  function probeInterpreter() { interpreterProbe.reload() }

  function applyState(raw) {
    var data = null
    try { data = raw && raw.trim() !== "" ? JSON.parse(raw) : null } catch (e) { console.warn("zorkmachy: unreadable state file, starting fresh: " + e) }
    var clean = Games.sanitizeState(data)
    games = clean.games
    current = clean.current
    loaded = true
    revision += 1
    if (current !== "") launch(current)
  }

  function save() {
    if (!loaded) return
    if (!dirReady) { pendingSave = true; return }
    stateFile.setText(JSON.stringify({ version: 1, current: current, games: games }, null, 1) + "\n")
  }

  onDirReadyChanged: if (dirReady && pendingSave) { pendingSave = false; save() }

  Component.onCompleted: if (active) mkdir.running = true
  onActiveChanged: {
    if (active && !loaded && !mkdir.running) mkdir.running = true
    if (!active) stop()
  }

  // QML only notices a `var` property when its value is a different object,
  // so every commit replaces the current game (and its transcript array)
  // with fresh copies. Mutating in place would leave the panels showing the
  // previous move.
  function commit() {
    var next = Object.assign({}, games)
    for (var key in next) {
      if (next[key] && next[key].transcript) next[key] = Object.assign({}, next[key], { transcript: next[key].transcript.slice() })
    }
    games = next
    revision += 1
    save()
  }

  // ---- the interpreter process -------------------------------------------

  Process {
    id: proc
    running: false
    stdinEnabled: true
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) { root.onChunk(data) }
    }
    stderr: SplitParser {
      onRead: function(line) { if (String(line).trim() !== "") console.warn("zorkmachy dfrotz: " + line) }
    }
    onExited: function(code, status) { root.onExited(code) }
  }

  function launch(key) {
    if (!Games.gameByKey(key)) return
    if (!interpreterAvailable) { probeInterpreter(); if (!interpreterAvailable) return }
    if (proc.running) {
      if (runningKey === key && phase !== "dead") return
      pendingLaunch = key
      proc.running = false
      return
    }
    var meta = Games.gameByKey(key)
    buffer = ""
    bootText = ""
    error = ""
    runningKey = key
    phase = "booting"
    // -p plain text, -m no [MORE] prompts, -q quiet start, -w/-h a wide
    // screen (dfrotz caps width at 255; the parser re-joins those wraps),
    // -R jails every file the interpreter reads or writes to the state dir.
    proc.command = [interpreter, "-p", "-m", "-q", "-w", "255", "-h", "200", "-R", stateDir, pluginDir + "/games/" + meta.file]
    proc.running = true
  }

  function stop() {
    pendingLaunch = ""
    if (proc.running) proc.running = false
    phase = "off"
    runningKey = ""
  }

  function onExited(code) {
    var wanted = pendingLaunch
    pendingLaunch = ""
    var wasRunning = runningKey
    runningKey = ""
    if (phase !== "off" && wanted === "") {
      phase = "dead"
      if (wasRunning !== "" && code !== 0) error = "The interpreter stopped unexpectedly (exit " + code + ")."
    } else {
      phase = "off"
    }
    if (wanted !== "") launch(wanted)
  }

  function onChunk(data) {
    buffer += String(data)
    var kind = Games.promptKind(buffer)
    if (kind !== "") handlePrompt(kind)
  }

  function write(line) { proc.write(line + "\n") }

  function saveName() { return runningKey + ".qzl" }

  // The conversation with dfrotz, one prompt at a time.
  function handlePrompt(kind) {
    var key = runningKey
    var game = gameState(key)
    var response
    switch (phase) {
    case "booting":
      if (kind !== "prompt") { answerStray(kind); return }
      response = Games.parseResponse(Games.stripPrompt(buffer))
      buffer = ""
      bootText = response.text
      if (game.started) {
        phase = "restoring"
        write("restore")
      } else {
        beginFresh(game, response)
      }
      return
    case "restoring":
      if (kind !== "filename") { answerStray(kind); return }
      buffer = ""
      phase = "restoreName"
      write(saveName())
      return
    case "restoreName":
      if (kind !== "prompt") { answerStray(kind); return }
      response = Games.parseResponse(Games.stripPrompt(buffer))
      buffer = ""
      if (/^Ok\./.test(response.text)) {
        applyStatus(game, response.status)
        Games.pushEntry(game, "sys", "Resumed" + (game.room !== "" ? " at " + game.room : "") + ".")
        phase = "idle"
        commit()
      } else {
        // No usable save: the game is sitting at its opening, so play from there.
        game.transcript = []
        Games.pushEntry(game, "sys", "The last save couldn't be read, so this game starts over.")
        beginFresh(game, { status: null, text: bootText })
      }
      return
    case "command":
      if (kind !== "prompt") { answerStray(kind); return }
      response = Games.parseResponse(Games.stripPrompt(buffer))
      buffer = ""
      applyStatus(game, response.status)
      if (response.text !== "") Games.pushEntry(game, "out", response.text)
      game.updatedAt = Date.now()
      commit()
      autosave()
      return
    case "saving":
      if (kind !== "filename") { answerStray(kind); return }
      buffer = ""
      phase = "saveName"
      write(saveName())
      return
    case "saveName":
      // Every save after the first replaces the previous one.
      if (kind === "overwrite") { buffer = ""; write("y"); return }
      if (kind !== "prompt") { answerStray(kind); return }
      response = Games.parseResponse(Games.stripPrompt(buffer))
      buffer = ""
      if (!/^Ok\./.test(response.text)) {
        error = "Couldn't save the game: " + response.text.split("\n")[0]
        console.warn("zorkmachy: save failed: " + response.text)
      } else if (!game.started) {
        game.started = true
        commit()
      }
      phase = "idle"
      return
    default:
      buffer = ""
    }
  }

  function beginFresh(game, response) {
    applyStatus(game, response.status)
    if (response.text !== "") Games.pushEntry(game, "out", response.text)
    game.updatedAt = Date.now()
    commit()
    autosave()
  }

  function autosave() {
    phase = "saving"
    write("save")
  }

  // A prompt we didn't expect at this point (a yes/no from inside the game,
  // a filename from some verb we don't intercept): answer harmlessly and
  // carry on. Under -R any file lands in the state directory anyway.
  function answerStray(kind) {
    buffer = ""
    if (kind === "yesno") write("n")
    else if (kind === "overwrite") write("n")
    else if (kind === "filename") write("scratch.qzl")
  }

  function applyStatus(game, status) {
    if (!status) return
    game.room = status.room
    game.score = status.score
    game.moves = status.moves
  }

  // ---- actions -----------------------------------------------------------

  function selectGame(key) {
    if (!Games.gameByKey(key)) return
    gameState(key)
    current = key
    error = ""
    commit()
    launch(key)
  }

  function showPicker() {
    current = ""
    commit()
  }

  // Start a game over: kill the interpreter, forget the transcript, and the
  // next autosave overwrites the old save file.
  function restartGame(key) {
    if (!Games.gameByKey(key)) return
    games[key] = Games.freshGame()
    error = ""
    if (runningKey === key || pendingLaunch === key) {
      pendingLaunch = key === current ? key : ""
      if (proc.running) proc.running = false
      else if (pendingLaunch !== "") { pendingLaunch = ""; launch(key) }
    } else if (key === current) {
      launch(key)
    }
    commit()
  }

  function send(text) {
    if (!ready) return false
    var command = Games.sanitizeCommand(text)
    if (command === "") return false
    var game = gameState(current)
    Games.pushEntry(game, "in", command)
    var message = Games.intercept(command)
    if (message !== "") {
      Games.pushEntry(game, "sys", message)
      commit()
      return true
    }
    commit()
    buffer = ""
    phase = "command"
    write(command)
    return true
  }

  // Commands typed into this game, newest last, for the input history.
  function history(key) {
    var game = games[key]
    if (!game) return []
    var out = []
    for (var i = 0; i < game.transcript.length; i++) if (game.transcript[i].k === "in") out.push(game.transcript[i].t)
    return out
  }

  Component.onDestruction: stop()
}
