#!/usr/bin/env node
// Checks the dfrotz output parsing against captured real output.
// Run: node test/parse.js
"use strict"
const fs = require("fs"), path = require("path"), vm = require("vm")
const src = fs.readFileSync(path.join(__dirname, "..", "Games.js"), "utf8").replace(/^\.pragma library\s*/m, "")
const G = {}
vm.runInNewContext(src + "\nthis.X = { parseResponse, promptKind, stripPrompt, sanitizeCommand, intercept, sanitizeState, isGameOverPrompt, GAMES }", G)
const X = G.X
let failures = 0
function eq(a, b, what) { if (JSON.stringify(a) !== JSON.stringify(b)) { failures++; console.error("FAIL " + what + ": got " + JSON.stringify(a) + " expected " + JSON.stringify(b)) } }

const pad = " ".repeat(200)
const boot = " West of House" + pad + "Score: 0        Moves: 0\n\nZORK I: The Great Underground Empire\nInfocom interactive fiction - a fantasy story\n\nWest of House\nYou are standing in an open field west of a white house, with a boarded front door.\nThere is a small mailbox here.\n\n>"
eq(X.promptKind(boot), "prompt", "boot prompt")
eq(X.promptKind(boot.slice(0, -1)), "", "no prompt yet")
eq(X.promptKind(boot + " "), "prompt", "prompt with trailing space")
const r = X.parseResponse(X.stripPrompt(boot))
eq(r.status, { room: "West of House", score: 0, moves: 0 }, "boot status")
eq(r.text.split("\n")[0], "ZORK I: The Great Underground Empire", "boot text start")
eq(r.text.endsWith("There is a small mailbox here."), true, "boot text end")

eq(X.promptKind("Please enter a filename [zork1.qzl]: "), "filename", "filename prompt")
eq(X.promptKind("Your score is 0 (total of 350 points), in 2 moves.\nDo you wish to leave the game? (Y is affirmative): >"), "yesno", "yes/no prompt")
eq(X.promptKind("Ok.\n\n>"), "prompt", "save ok prompt")
eq(X.promptKind("Overwrite existing file? "), "overwrite", "overwrite prompt")
eq(X.promptKind(" Cellar" + pad + "Score: 25        Moves: 14\n\nOk.\n\n>"), "prompt", "restore ok")
eq(X.parseResponse(" Cellar" + pad + "Score: 25        Moves: 14\n\nOk.\n\n").status, { room: "Cellar", score: 25, moves: 14 }, "restore status")
eq(X.parseResponse("Ok.\n\n").status, null, "no status line")
eq(X.parseResponse("Ok.\n\n").text, "Ok.", "plain text")
eq(X.parseResponse(" Living Room" + pad + "Score: -5        Moves: 99\n\nYou have moved into a dark place.\n\n").status.score, -5, "negative score")
const long = "You are in the kitchen of the white house. A table seems to have been used recently for the preparation of food. A passage leads to the west and a dark staircase can be seen leading upward. A dark chimney leads down and to the east is a small"
eq(X.parseResponse("Kitchen\n" + long + "\nwindow which is open.\nA bottle is sitting on the table.\nThe glass bottle contains:\n  A quantity of water\n").text, "Kitchen\n" + long + " window which is open.\nA bottle is sitting on the table.\nThe glass bottle contains:\n  A quantity of water", "unwrap hard wrap only")
eq(X.parseResponse("Short line\nnext line\n").text, "Short line\nnext line", "short lines untouched")

eq(X.sanitizeCommand("  open\tthe   mailbox\n\nquit "), "open the mailbox quit", "sanitize")
eq(X.sanitizeCommand("x".repeat(300)).length, 200, "cap length")
eq(X.intercept("SAVE") !== "", true, "intercept save")
eq(X.intercept("look"), "", "look passes")
eq(X.isGameOverPrompt("...(Type RESTART, RESTORE, or QUIT):"), true, "game over")

const s = X.sanitizeState({ current: "zork2", games: { zork2: { started: true, room: "x".repeat(200), score: "9", moves: 12.5, transcript: [{ k: "in", t: "look" }, { k: "evil", t: "x" }, null, { k: "out", t: 5 }] }, zork9: {} } })
eq(s.current, "zork2", "current kept")
eq(s.games.zork2.room.length, 80, "room capped")
eq(s.games.zork2.score, 0, "bad score dropped")
eq(s.games.zork2.moves, 0, "bad moves dropped")
eq(s.games.zork2.transcript, [{ k: "in", t: "look" }], "transcript filtered")
eq(Object.keys(s.games).sort(), ["zork1", "zork2", "zork3"], "all games present")
eq(X.sanitizeState("junk").current, "", "junk state")
eq(X.sanitizeState({ current: "zork9" }).current, "", "unknown game")

console.log(failures ? failures + " failures" : "ok")
process.exit(failures ? 1 : 0)
