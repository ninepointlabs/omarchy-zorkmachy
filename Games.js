.pragma library

// The three games Zorkmachy ships, and the small amount of parsing needed to
// talk to dfrotz over a pipe. Nothing here touches QML, so test/parse.js can
// exercise it from Node.

var GAMES = [
  {
    key: "zork1", file: "zork1.z3", numeral: "I",
    title: "Zork I", subtitle: "The Great Underground Empire", year: 1980, maxScore: 350,
    blurb: "You are standing in an open field west of a white house. Somewhere below lies the Great Underground Empire and the twenty treasures of Zork."
  },
  {
    key: "zork2", file: "zork2.z3", numeral: "II",
    title: "Zork II", subtitle: "The Wizard of Frobozz", year: 1981, maxScore: 400,
    blurb: "Deeper still, a bumbling wizard, a dragon, and the puzzles that made the Carousel Room famous."
  },
  {
    key: "zork3", file: "zork3.z3", numeral: "III",
    title: "Zork III", subtitle: "The Dungeon Master", year: 1982, maxScore: 7,
    blurb: "The end of the road: fewer points, harder choices, and a final test of who you have become."
  }
]

function gameByKey(key) {
  for (var i = 0; i < GAMES.length; i++) if (GAMES[i].key === key) return GAMES[i]
  return null
}

// dfrotz -p prints a status line before each response: the room name, then
// a run of spaces, then "Score: N        Moves: N".
var STATUS_RE = /^\s*(.*?)\s{2,}Score:\s*(-?\d+)\s+Moves:\s*(\d+)\s*$/

// One complete response from the interpreter (everything since the last
// command, minus the prompt) becomes a status update and a block of text.
function parseResponse(raw) {
  var lines = String(raw || "").replace(/\r/g, "").split("\n")
  var status = null
  var i = 0
  while (i < lines.length && lines[i].trim() === "") i++
  var m = i < lines.length ? lines[i].match(STATUS_RE) : null
  if (m) {
    status = { room: m[1].trim(), score: Number(m[2]), moves: Number(m[3]) }
    lines.splice(0, i + 1)
  }
  var text = unwrap(lines).join("\n").replace(/^\n+/, "").replace(/\s+$/, "")
  return { status: status, text: text }
}

// dfrotz hard-wraps at 255 columns no matter what -w says. A line that runs
// right up to that limit and stops mid-sentence is a wrap, not a paragraph
// break, so glue the next line back on and let the panel wrap it properly.
var WRAP_WIDTH = 255
function unwrap(lines) {
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var prev = out.length ? out[out.length - 1] : null
    if (prev !== null && prev.length >= WRAP_WIDTH - 40 && !/[.!?:"')\]]$/.test(prev) && line !== "" && !/^\s/.test(line)) {
      out[out.length - 1] = prev + " " + line
    } else {
      out.push(line)
    }
  }
  return out
}

// What the interpreter is waiting for, judging by the tail of its output:
//   "prompt"    the game's ">"; a command can be sent
//   "filename"  dfrotz asking where to save/restore
//   "overwrite" dfrotz asking before replacing an existing save
//   "yesno"     "(Y is affirmative)" after quit/restart
//   ""          still printing
function promptKind(buffer) {
  var t = String(buffer || "").replace(/[ \t]+$/, "")
  if (/Please enter a filename \[[^\]]*\]:\s*$/.test(buffer)) return "filename"
  if (/Overwrite existing file\?\s*$/.test(buffer)) return "overwrite"
  if (/\(Y is affirmative\):\s*>?$/.test(t)) return "yesno"
  if (t === ">" || /\n>$/.test(t)) return "prompt"
  return ""
}

// Everything before the trailing prompt.
function stripPrompt(buffer) {
  return String(buffer || "").replace(/[ \t]+$/, "").replace(/>$/, "")
}

// Player input goes to the game's stdin one line at a time, so it must be
// one line of printable text.
function sanitizeCommand(text) {
  return String(text || "").replace(/[\x00-\x1f\x7f]/g, " ").replace(/\s+/g, " ").trim().slice(0, 200)
}

// Commands that would take the interpreter somewhere the panel doesn't
// follow (its own save prompts, a quit that kills the process). Zorkmachy
// handles all of these itself.
function intercept(command) {
  var c = command.toLowerCase()
  if (c === "save") return "No need: Zorkmachy saves your game after every move."
  if (c === "restore") return "Your game is restored automatically whenever you come back. Use Restart to begin again."
  if (c === "restart") return "Click Restart above to start this game over."
  if (c === "quit" || c === "q") return "Just close the panel; your game is saved. Use Games to pick another Zork."
  if (c === "script" || c === "unscript") return "Transcripts are kept by the panel; scroll up to read back."
  return ""
}

function isGameOverPrompt(text) {
  return /Type RESTART, RESTORE, or QUIT/i.test(text) || /\*\*\*\*\s+You have died\s+\*\*\*\*/.test(text)
}

function freshGame() {
  return { started: false, room: "", score: 0, moves: 0, transcript: [], updatedAt: 0 }
}

var TRANSCRIPT_LIMIT = 300

function pushEntry(game, kind, text) {
  game.transcript.push({ k: kind, t: text })
  if (game.transcript.length > TRANSCRIPT_LIMIT) game.transcript.splice(0, game.transcript.length - TRANSCRIPT_LIMIT)
}

// The state file is the only thing read from disk: keep only well-formed
// entries so a bad file can't crash the shell or feed junk into the panel.
function sanitizeState(data) {
  var out = { current: "", games: {} }
  if (!data || typeof data !== "object") return out
  if (typeof data.current === "string" && gameByKey(data.current)) out.current = data.current
  var games = data.games && typeof data.games === "object" ? data.games : {}
  for (var i = 0; i < GAMES.length; i++) {
    var key = GAMES[i].key
    var g = games[key]
    var clean = freshGame()
    if (g && typeof g === "object") {
      clean.started = g.started === true
      clean.room = typeof g.room === "string" ? g.room.slice(0, 80) : ""
      clean.score = isInt(g.score, -100000, 100000) ? g.score : 0
      clean.moves = isInt(g.moves, 0, 10000000) ? g.moves : 0
      clean.updatedAt = isInt(g.updatedAt, 0, 1e14) ? g.updatedAt : 0
      if (Array.isArray(g.transcript)) {
        for (var t = Math.max(0, g.transcript.length - TRANSCRIPT_LIMIT); t < g.transcript.length; t++) {
          var e = g.transcript[t]
          if (e && typeof e === "object" && typeof e.t === "string" && ["in", "out", "sys"].indexOf(e.k) >= 0)
            clean.transcript.push({ k: e.k, t: e.t.slice(0, 4000) })
        }
      }
    }
    out.games[key] = clean
  }
  return out
}

function isInt(v, lo, hi) {
  return typeof v === "number" && isFinite(v) && Math.floor(v) === v && v >= lo && v <= hi
}
