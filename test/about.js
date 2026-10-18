#!/usr/bin/env node
// Checks the About page's facts against the repo, and that the privacy
// statement names every network host the code could reach.
// Run: node test/about.js
"use strict"
const fs = require("fs"), path = require("path"), vm = require("vm")
const root = path.join(__dirname, "..")
const read = (f) => fs.readFileSync(path.join(root, f), "utf8")
const src = read("Games.js").replace(/^\.pragma library\s*/m, "")
const G = {}
vm.runInNewContext(src + "\nthis.X = { ABOUT, PRIVACY, manifestVersion, probedVersion, frotzVersion, reflowLicense, builtWith, aboutDetails, supportMailto }", G)
const X = G.X
let failures = 0
function eq(a, b, what) { if (JSON.stringify(a) !== JSON.stringify(b)) { failures++; console.error("FAIL " + what + ": got " + JSON.stringify(a) + " expected " + JSON.stringify(b)) } }
function ok(cond, what) { eq(!!cond, true, what) }

// Facts from the repo's own files.
const manifest = JSON.parse(read("manifest.json"))
eq(X.manifestVersion(read("manifest.json")), manifest.version, "version from manifest.json")
eq(X.manifestVersion("not json"), "", "bad manifest")
eq(X.manifestVersion('{"version":"1.0 <b>"}'), "", "odd version refused")
eq(manifest.author, "Nine Point Labs", "manifest author")
eq(X.ABOUT.name, manifest.name, "name")
eq(X.ABOUT.organization, "Nine Point Labs", "organization")
eq(X.ABOUT.supportEmail, "help@ninepointlabs.com", "support email")
const license = read("LICENSE")
ok(license.startsWith(X.ABOUT.license + "\n"), "license name matches LICENSE")
ok(license.includes(X.ABOUT.copyright.replace("©", "Copyright (c)")), "copyright matches LICENSE")
const gamesLicense = read("games/LICENSE")
ok(gamesLicense.startsWith("MIT License") && gamesLicense.includes("Copyright (c) 2025 Microsoft"), "games/LICENSE is Microsoft's MIT")
ok(X.ABOUT.games.includes("MIT License (© 2025 Microsoft)") && X.ABOUT.games.includes("Infocom"), "games credit")
for (const name of read("games/SOURCES.txt").trim().split("\n").map((l) => l.split(" ")[0]))
  ok(X.ABOUT.games.includes(name), "games credit names " + name)
const first = require("child_process").execSync("git -C " + JSON.stringify(root) + " log --reverse --format=%ad --date=format:'%B %Y' 2>/dev/null || true").toString().split("\n")[0]
if (first) eq(X.ABOUT.created, first, "created = first commit month")
ok(!/Ninepoint|NINEPOINT LABS/.test(read("LICENSE") + read("manifest.json") + read("README.md") + src), "spelled Nine Point Labs")

// Helpers.
const reflowed = X.reflowLicense(license)
ok(reflowed.startsWith("MIT License\n\nCopyright (c) 2026 Nine Point Labs\n\nPermission"), "license reflowed")
ok(!reflowed.includes("a copy\nof"), "license lines joined")
eq(X.probedVersion((major, minor) => major === 6 && minor <= 11, 6), "6.11", "probe qt")
eq(X.probedVersion((major, minor) => major === 0 && minor <= 3, 0), "0.3", "probe quickshell")
eq(X.probedVersion(() => false, 6), "", "probe none")
eq(X.probedVersion(null, 6), "", "probe null")
eq(X.frotzVersion("FROTZ V2.55     Dumb interface."), "2.55", "frotz version")
eq(X.frotzVersion("Commit date:    2025-02-01"), "", "frotz other line")
const details = X.aboutDetails("0.1.0", "0.3", "6.11", "2.55", "Hyprland, wayland")
eq(details, "Zorkmachy 0.1.0\nQuickshell 0.3, Qt 6.11, frotz 2.55\nHyprland, wayland", "details")
const mail = X.supportMailto("0.1.0", details)
ok(mail.startsWith("mailto:help@ninepointlabs.com?subject=Zorkmachy%200.1.0&body="), "mailto subject")
ok(decodeURIComponent(mail.split("&body=")[1]).endsWith("frotz 2.55\nHyprland, wayland"), "mailto body")

// Privacy: true to the code. Every host named anywhere in the shipped code
// must appear in the statement; today there are none, so it says so.
ok(X.PRIVACY.includes("no network connections") && X.PRIVACY.includes("no telemetry"), "privacy says no network, no telemetry")
ok(X.PRIVACY.includes("~/.local/state/omarchy-zorkmachy/"), "privacy names the state dir")
ok(X.PRIVACY.includes("shell.json"), "privacy names shell.json")
const serviceSrc = read("Service.qml")
ok(serviceSrc.includes('"/.local/state/omarchy-zorkmachy"'), "state dir in Service.qml matches")
const shipped = ["Games.js", "Service.qml", "BarWidget.qml", "Panel.qml", "install.sh"]
for (const f of shipped) {
  const text = read(f)
  const hosts = new Set()
  for (const m of text.matchAll(/\b[a-z][a-z0-9+.-]*:\/\/([^\/\s"'`)]+)/gi)) if (!/^file:/i.test(m[0])) hosts.add(m[1].replace(/^.*@/, ""))
  for (const m of text.matchAll(/@([a-z0-9-]+(?:\.[a-z0-9-]+)+)/gi)) hosts.add(m[1])
  for (const host of hosts) ok(X.PRIVACY.includes(host) || host === "ninepointlabs.com", f + ": host " + host + " is named in the privacy statement")
  for (const api of ["XMLHttpRequest", "WebSocket", "NetworkRequest", "curl", "wget", "fetch("])
    ok(!text.includes(api) || X.PRIVACY.includes(api), f + ": uses " + api + " without a privacy note")
}

console.log(failures ? failures + " failures" : "ok")
process.exit(failures ? 1 : 0)
