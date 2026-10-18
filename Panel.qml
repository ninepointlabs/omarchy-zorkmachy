import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Games.js" as Games

// The Zorkmachy panel: pick one of the three Zorks, then a transcript with
// an input line, the way the game has always looked. The service owns the
// interpreter and the saves; this file only renders and forwards input.
Panel {
  id: root
  moduleName: "ninepointlabs.zorkmachy"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var sharedService: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null
  readonly property var service: sharedService || localService

  function pushSettings() { if (service) service.settings = settings }
  onSettingsChanged: pushSettings()
  onServiceChanged: pushSettings()
  Component.onCompleted: pushSettings()

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color faint: Qt.darker(foreground, 2.1)

  // ---------------------------------------------------------------- state --

  readonly property int revision: service ? service.revision : 0
  readonly property string current: service && revision >= 0 ? service.current : ""
  readonly property var game: service && revision >= 0 ? service.currentGame : null
  readonly property var meta: current !== "" ? Games.gameByKey(current) : null
  readonly property var transcript: game && revision >= 0 ? game.transcript : []
  readonly property bool busy: service ? service.busy : false
  readonly property bool ready: service ? service.ready : false
  readonly property string serviceError: service ? service.error : ""

  readonly property string mode: {
    if (showAbout) return "about"
    if (!service || !service.loaded) return "loading"
    if (service.interpreterProbed && !service.interpreterAvailable) return "setup"
    if (current === "") return "picker"
    return "game"
  }

  property string confirmRestartKey: ""

  // ---------------------------------------------------------------- about --
  // The About page replaces the panel's content (info button or the `about`
  // IPC call; Back or Escape returns, closing the panel resets it). Its facts
  // are read from the plugin's own files, only once it is shown.
  property bool showAbout: false
  property string licenseShown: ""   // "" | "plugin" | "games"
  property string copiedLabel: ""
  property string frotzVersion: ""

  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")).replace(/\/$/, "")
  readonly property string version: Games.manifestVersion(manifestFile.loaded ? manifestFile.text() : "")
  readonly property string quickshellVersion: Games.probedVersion(function(a, b) { return Quickshell.hasVersion(a, b) }, 0)
  readonly property string qtVersion: Games.probedVersion(function(a, b) { return Quickshell.hasQtVersion(a, b) }, 6)
  readonly property string aboutDetails: Games.aboutDetails(root.version, root.quickshellVersion, root.qtVersion, root.frotzVersion,
    (Quickshell.env("XDG_CURRENT_DESKTOP") || "unknown desktop") + ", " + Qt.platform.pluginName)

  FileView { id: manifestFile; path: root.showAbout ? root.pluginDir + "/manifest.json" : ""; printErrors: false }
  FileView { id: licenseFile; path: root.licenseShown === "plugin" ? root.pluginDir + "/LICENSE" : (root.licenseShown === "games" ? root.pluginDir + "/games/LICENSE" : ""); printErrors: false }

  // `dfrotz -v` only prints its version and exits.
  Process {
    id: frotzProbe
    command: [root.service ? root.service.interpreter : "/usr/bin/dfrotz", "-v"]
    running: false
    stdout: SplitParser {
      onRead: function(line) { if (root.frotzVersion === "") root.frotzVersion = Games.frotzVersion(line) }
    }
  }

  function showAboutPage() {
    confirmRestartKey = ""
    licenseShown = ""
    showAbout = true
    if (frotzVersion === "" && !frotzProbe.running && service && service.interpreterAvailable) frotzProbe.running = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function closeAbout() {
    showAbout = false
    licenseShown = ""
    Qt.callLater(function() {
      if (root.mode === "game") { inputField.forceActiveFocus(); root.scrollToEnd() }
      else keyCatcher.forceActiveFocus()
    })
  }

  function copyText(text, label) {
    Quickshell.clipboardText = text
    copiedLabel = label
    copiedTimer.restart()
  }

  Timer { id: copiedTimer; interval: 1500; onTriggered: root.copiedLabel = "" }
  property int historyIndex: -1
  property string historyDraft: ""

  readonly property string statusText: {
    if (!game || !meta) return ""
    var parts = [meta.title]
    if (game.room !== "") parts.push(game.room)
    parts.push("Score " + game.score + "/" + meta.maxScore)
    parts.push(game.moves + " moves")
    return parts.join("  ·  ")
  }

  function gameSummary(key) {
    var g = service && service.games ? service.games[key] : null
    var m = Games.gameByKey(key)
    if (!g || !g.started) return "Not started"
    return (g.room !== "" ? g.room + "  ·  " : "") + "Score " + g.score + "/" + m.maxScore + "  ·  " + g.moves + " moves"
  }

  function gameStarted(key) {
    var g = service && service.games ? service.games[key] : null
    return g ? g.started === true : false
  }

  // -------------------------------------------------------------- actions --

  function submit() {
    if (!service) return
    var text = inputField.text
    if (text.trim() === "" || !ready) return
    if (service.send(text)) {
      inputField.text = ""
      historyIndex = -1
      historyDraft = ""
      scrollToEnd()
    }
  }

  function recallHistory(delta) {
    if (!service || current === "") return
    var items = service.history(current)
    if (items.length === 0) return
    if (historyIndex === -1) {
      if (delta > 0) return
      historyDraft = inputField.text
      historyIndex = items.length - 1
    } else {
      historyIndex += delta
      if (historyIndex >= items.length) { historyIndex = -1; inputField.text = historyDraft; return }
      if (historyIndex < 0) historyIndex = 0
    }
    inputField.text = items[historyIndex]
    inputField.cursorPosition = inputField.text.length
  }

  function pick(key) {
    if (!service) return
    confirmRestartKey = ""
    service.selectGame(key)
    Qt.callLater(function() { inputField.forceActiveFocus(); scrollToEnd() })
  }

  function backToGames() {
    if (!service) return
    confirmRestartKey = ""
    service.showPicker()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function restart(key) {
    if (!service) return
    confirmRestartKey = ""
    service.restartGame(key)
    if (key === current) Qt.callLater(function() { inputField.forceActiveFocus() })
  }

  function scrollToEnd() {
    Qt.callLater(function() {
      if (transcriptFlick) transcriptFlick.contentY = Math.max(0, transcriptFlick.contentHeight - transcriptFlick.height)
    })
  }

  function launchInstall() {
    if (!bar) return
    bar.run("omarchy-launch-floating-terminal-with-presentation " + Util.shellQuote("omarchy pkg add frotz-dumb"))
    close()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  onTranscriptChanged: scrollToEnd()

  implicitWidth: 1
  implicitHeight: 1

  onOpenedChanged: {
    confirmRestartKey = ""
    if (!opened) { showAbout = false; licenseShown = ""; return }
    if (service && service.interpreterProbed && !service.interpreterAvailable) service.probeInterpreter()
    Qt.callLater(function() {
      if (root.mode === "game") { inputField.forceActiveFocus(); root.scrollToEnd() }
      else keyCatcher.forceActiveFocus()
    })
  }

  // The shell mounts one shared service per plugin, but it can appear a
  // moment after the panels do. Only fall back to a private service if none
  // has shown up after a grace period, and step aside as soon as one does,
  // so two monitors never end up playing two different games.
  Service {
    id: localService
    active: false
  }
  Timer {
    interval: 2500
    running: root.bar !== null && root.sharedService === null && !localService.active
    onTriggered: if (root.sharedService === null) localService.active = true
  }
  onSharedServiceChanged: if (sharedService !== null && localService.active) localService.active = false

  // While the install card shows, re-check for the interpreter so finishing
  // the install in the terminal flips the panel over on its own.
  Timer {
    interval: 3000
    repeat: true
    running: root.opened && root.mode === "setup"
    onTriggered: if (root.service) root.service.probeInterpreter()
  }

  // --------------------------------------------------------------- pieces --

  component AboutLabel: Text {
    textFormat: Text.PlainText
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.Wrap
  }

  component AboutValue: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.Wrap
  }

  component AboutLink: Text {
    signal activated()
    textFormat: Text.PlainText
    color: root.accent
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption

    MouseArea {
      anchors.fill: parent
      anchors.margins: -Style.space(4)
      cursorShape: Qt.PointingHandCursor
      onClicked: parent.activated()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: root.mode === "game" ? inputField : keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(600))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(860))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: inputField.activeFocus
      onCloseRequested: {
        if (root.confirmRestartKey !== "") { root.confirmRestartKey = ""; return }
        if (root.showAbout) { root.closeAbout(); return }
        root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (root.mode === "picker") {
          var n = Number(t)
          if (n >= 1 && n <= Games.GAMES.length) root.pick(Games.GAMES[n - 1].key)
        } else if (root.mode === "game") {
          inputField.forceActiveFocus()
          inputField.text += t
          inputField.cursorPosition = inputField.text.length
        }
      }

      Column {
        id: content
        anchors.fill: parent
        spacing: Style.space(10)

        // ------------------------------------------------------- header --
        Item {
          width: parent.width
          implicitHeight: Math.max(titleColumn.implicitHeight, headerActions.implicitHeight)

          Column {
            id: titleColumn
            anchors.left: parent.left
            anchors.right: headerActions.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Row {
              spacing: Style.space(6)
              Text {
                textFormat: Text.PlainText
                text: "󰆍"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                textFormat: Text.PlainText
                text: "Z O R K M A C H Y"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Text {
              visible: text !== ""
              width: parent.width
              textFormat: Text.PlainText
              text: root.mode === "game" ? root.statusText : (root.mode === "picker" ? "Which Zork, adventurer?" : (root.mode === "about" ? "About" : ""))
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
          }

          Row {
            id: headerActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            Button {
              objectName: "aboutBack"
              visible: root.mode === "about"
              iconText: "󰁍"
              text: "Back"
              tooltipText: "Back (Esc)"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              iconSize: Style.font.body
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(3)
              onClicked: root.closeAbout()
            }
            Button {
              visible: root.mode === "game" && root.confirmRestartKey === ""
              iconText: "󰅁"
              text: "Games"
              tooltipText: "Pick another Zork; this one stays saved"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              iconSize: Style.font.body
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(3)
              onClicked: root.backToGames()
            }
            Button {
              visible: root.mode === "game" && root.confirmRestartKey === ""
              text: "Restart"
              tooltipText: "Start this game over from the beginning"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(3)
              onClicked: root.confirmRestartKey = root.current
            }
            Text {
              visible: root.mode === "game" && root.confirmRestartKey !== ""
              textFormat: Text.PlainText
              text: "Start over and lose this game?"
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }
            Button {
              visible: root.mode === "game" && root.confirmRestartKey !== ""
              text: "Yes"
              bordered: true
              foreground: root.urgent
              accent: root.urgent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(3)
              onClicked: root.restart(root.confirmRestartKey)
            }
            Button {
              visible: root.mode === "game" && root.confirmRestartKey !== ""
              text: "No"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(3)
              onClicked: root.confirmRestartKey = ""
            }
            PanelActionButton {
              objectName: "aboutButton"
              visible: root.mode !== "about" && root.confirmRestartKey === ""
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰋽"
              tooltipText: "About Zorkmachy"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.showAboutPage()
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        // --------------------------------------------------------- about --
        Column {
          objectName: "aboutColumn"
          visible: root.mode === "about"
          width: parent.width
          spacing: Style.space(10)

          Row {
            width: parent.width
            spacing: Style.space(12)

            Text {
              id: aboutIcon
              textFormat: Text.PlainText
              text: "󰆍"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              anchors.verticalCenter: parent.verticalCenter
            }
            Column {
              width: parent.width - aboutIcon.width - parent.spacing
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              Text {
                textFormat: Text.PlainText
                text: Games.ABOUT.name
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }
              AboutValue { width: parent.width; text: Games.ABOUT.tagline }
              AboutLabel { objectName: "aboutVersion"; width: parent.width; text: "Version " + (root.version || "unknown") }
            }
          }

          Grid {
            id: aboutFacts
            width: parent.width
            columns: 2
            columnSpacing: Style.space(12)
            rowSpacing: Style.space(8)
            readonly property real labelWidth: Style.space(84)
            readonly property real valueWidth: width - labelWidth - columnSpacing

            AboutLabel { width: aboutFacts.labelWidth; text: "MADE BY" }
            AboutValue { width: aboutFacts.valueWidth; text: Games.ABOUT.organization }

            AboutLabel { width: aboutFacts.labelWidth; text: "CREATED" }
            AboutValue { width: aboutFacts.valueWidth; text: Games.ABOUT.created }

            AboutLabel { width: aboutFacts.labelWidth; text: "LICENSE" }
            Column {
              width: aboutFacts.valueWidth
              spacing: Style.space(2)
              AboutValue { width: parent.width; text: Games.ABOUT.license + ", " + Games.ABOUT.copyright }
              AboutLink {
                objectName: "aboutLicenseLink"
                text: root.licenseShown === "plugin" ? "Hide license" : "Read license"
                onActivated: root.licenseShown = root.licenseShown === "plugin" ? "" : "plugin"
              }
            }

            AboutLabel { width: aboutFacts.labelWidth; text: "THE GAMES" }
            Column {
              width: aboutFacts.valueWidth
              spacing: Style.space(2)
              AboutValue { objectName: "aboutGames"; width: parent.width; text: Games.ABOUT.games }
              AboutLink {
                objectName: "aboutGamesLicenseLink"
                text: root.licenseShown === "games" ? "Hide the games' license" : "Read the games' license"
                onActivated: root.licenseShown = root.licenseShown === "games" ? "" : "games"
              }
            }

            AboutLabel { width: aboutFacts.labelWidth; text: "SUPPORT" }
            Column {
              width: aboutFacts.valueWidth
              spacing: Style.space(4)
              AboutValue { width: parent.width; text: Games.ABOUT.supportEmail }
              Flow {
                width: parent.width
                spacing: Style.space(6)
                Button {
                  text: "Email"
                  tooltipText: "Opens your mail app with the version details filled in"
                  bordered: true
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  horizontalPadding: Style.space(8)
                  verticalPadding: Style.space(3)
                  onClicked: Qt.openUrlExternally(Games.supportMailto(root.version, root.aboutDetails))
                }
                Button {
                  objectName: "aboutCopyEmail"
                  text: root.copiedLabel === "email" ? "Copied" : "Copy"
                  bordered: true
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  horizontalPadding: Style.space(8)
                  verticalPadding: Style.space(3)
                  onClicked: root.copyText(Games.ABOUT.supportEmail, "email")
                }
                Button {
                  objectName: "aboutCopyDetails"
                  text: root.copiedLabel === "details" ? "Copied" : "Copy version details"
                  bordered: true
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  horizontalPadding: Style.space(8)
                  verticalPadding: Style.space(3)
                  onClicked: root.copyText(root.aboutDetails, "details")
                }
              }
            }

            AboutLabel { width: aboutFacts.labelWidth; text: "PRIVACY" }
            AboutValue { objectName: "aboutPrivacy"; width: aboutFacts.valueWidth; text: Games.PRIVACY }

            AboutLabel { width: aboutFacts.labelWidth; text: "BUILT WITH" }
            Column {
              width: aboutFacts.valueWidth
              spacing: Style.space(2)
              AboutValue { objectName: "aboutBuiltWith"; width: parent.width; text: Games.builtWith(root.quickshellVersion, root.qtVersion, root.frotzVersion) }
              AboutLabel { width: parent.width; text: "Interpreter: " + Games.ABOUT.interpreter }
            }
          }

          Rectangle {
            visible: root.licenseShown !== ""
            width: parent.width
            height: Style.space(200)
            radius: Style.cornerRadius
            color: Style.normalFillFor(root.foreground, root.accent)
            border.width: Style.spacing.hairline
            border.color: Style.normalBorderFor(root.foreground, root.accent)
            clip: true

            Flickable {
              id: licenseFlick
              anchors.fill: parent
              anchors.margins: Style.space(10)
              contentWidth: width
              contentHeight: licenseText.implicitHeight
              boundsBehavior: Flickable.StopAtBounds

              AboutLabel {
                id: licenseText
                objectName: "aboutLicenseText"
                width: licenseFlick.width
                text: licenseFile.loaded ? Games.reflowLicense(licenseFile.text())
                  : (root.licenseShown === "games" ? "See games/LICENSE in the plugin folder." : "See LICENSE in the plugin folder.")
              }
            }
          }
        }

        // ------------------------------------------------------- loading --
        Text {
          visible: root.mode === "loading"
          textFormat: Text.PlainText
          text: "Loading…"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        // --------------------------------------------------------- setup --
        Column {
          visible: root.mode === "setup"
          width: parent.width
          spacing: Style.space(10)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Zorkmachy needs the frotz Z-machine interpreter"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            wrapMode: Text.Wrap
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "The three Zork games are included with the plugin. To run them it uses dfrotz from the Arch package frotz-dumb, which isn't installed yet. This button opens a terminal that runs `omarchy pkg add frotz-dumb`; the panel takes over as soon as it's there."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
          }
          Button {
            text: "Install frotz-dumb…"
            bordered: true
            foreground: root.foreground
            background: Color.popups.background
            accent: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.body
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.launchInstall()
          }
        }

        // -------------------------------------------------------- picker --
        Column {
          visible: root.mode === "picker"
          width: parent.width
          spacing: Style.space(8)

          Repeater {
            model: Games.GAMES
            Rectangle {
              required property var modelData
              required property int index
              readonly property bool started: root.gameStarted(modelData.key)
              readonly property bool confirming: root.confirmRestartKey === modelData.key
              width: parent.width
              radius: Style.cornerRadius
              color: cardMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.accent) : Style.normalFillFor(root.foreground, root.accent)
              border.width: Style.spacing.hairline
              border.color: Style.normalBorderFor(root.foreground, root.accent)
              implicitHeight: cardColumn.implicitHeight + Style.space(20)

              MouseArea {
                id: cardMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.pick(modelData.key)
              }

              Column {
                id: cardColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(10)
                spacing: Style.space(4)

                Row {
                  width: parent.width
                  spacing: Style.space(8)
                  Text {
                    textFormat: Text.PlainText
                    text: String(index + 1) + "."
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: modelData.title + ": " + modelData.subtitle
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: "Infocom, " + modelData.year
                    color: root.faint
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: modelData.blurb
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.Wrap
                }

                Item {
                  width: parent.width
                  implicitHeight: Math.max(summaryText.implicitHeight, cardButtons.implicitHeight)

                  Text {
                    id: summaryText
                    anchors.left: parent.left
                    anchors.right: cardButtons.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: confirming ? "Start over and lose this game?" : root.gameSummary(modelData.key)
                    color: confirming ? root.urgent : (started ? root.foreground : root.faint)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }

                  Row {
                    id: cardButtons
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(4)

                    Button {
                      visible: !confirming
                      text: started ? "Continue" : "Play"
                      bordered: true
                      foreground: root.foreground
                      accent: root.accent
                      fontFamily: root.fontFamily
                      fontSize: Style.font.caption
                      horizontalPadding: Style.space(10)
                      verticalPadding: Style.space(3)
                      onClicked: root.pick(modelData.key)
                    }
                    Button {
                      visible: started && !confirming
                      text: "Restart"
                      foreground: root.dim
                      accent: root.accent
                      fontFamily: root.fontFamily
                      fontSize: Style.font.caption
                      horizontalPadding: Style.space(8)
                      verticalPadding: Style.space(3)
                      onClicked: root.confirmRestartKey = modelData.key
                    }
                    Button {
                      visible: confirming
                      text: "Yes"
                      bordered: true
                      foreground: root.urgent
                      accent: root.urgent
                      fontFamily: root.fontFamily
                      fontSize: Style.font.caption
                      horizontalPadding: Style.space(8)
                      verticalPadding: Style.space(3)
                      onClicked: root.restart(modelData.key)
                    }
                    Button {
                      visible: confirming
                      text: "No"
                      foreground: root.foreground
                      accent: root.accent
                      fontFamily: root.fontFamily
                      fontSize: Style.font.caption
                      horizontalPadding: Style.space(8)
                      verticalPadding: Style.space(3)
                      onClicked: root.confirmRestartKey = ""
                    }
                  }
                }
              }
            }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Zork I, II and III are © Infocom, released under the MIT licence by Microsoft in 2025. Every game saves itself after each move."
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
          }
        }

        // ---------------------------------------------------- transcript --
        Rectangle {
          visible: root.mode === "game"
          width: parent.width
          height: Style.space(520)
          radius: Style.cornerRadius
          color: Style.normalFillFor(root.foreground, root.accent)
          border.width: Style.spacing.hairline
          border.color: Style.normalBorderFor(root.foreground, root.accent)
          clip: true

          Flickable {
            id: transcriptFlick
            anchors.fill: parent
            anchors.margins: Style.space(10)
            contentWidth: width
            contentHeight: transcriptColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            onContentHeightChanged: contentY = Math.max(0, contentHeight - height)

            Column {
              id: transcriptColumn
              width: transcriptFlick.width
              spacing: Style.space(6)

              Text {
                visible: root.transcript.length === 0
                width: parent.width
                textFormat: Text.PlainText
                text: root.busy ? "Starting the interpreter…" : ""
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Repeater {
                model: root.transcript
                Text {
                  required property var modelData
                  width: parent.width
                  textFormat: Text.PlainText
                  text: modelData.k === "in" ? "> " + modelData.t : modelData.t
                  color: modelData.k === "in" ? root.accent : (modelData.k === "sys" ? root.dim : root.foreground)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: modelData.k === "in"
                  font.italic: modelData.k === "sys"
                  wrapMode: Text.Wrap
                }
              }

              Text {
                visible: root.busy && root.transcript.length > 0
                textFormat: Text.PlainText
                text: "…"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                visible: root.serviceError !== ""
                width: parent.width
                textFormat: Text.PlainText
                text: root.serviceError
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.Wrap
              }
            }
          }
        }

        // --------------------------------------------------------- input --
        Row {
          visible: root.mode === "game"
          width: parent.width
          spacing: Style.space(6)

          Text {
            textFormat: Text.PlainText
            text: ">"
            color: root.ready ? root.accent : root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }

          TextField {
            id: inputField
            width: parent.width - Style.space(20) - parent.spacing
            placeholderText: root.ready ? "What do you do?" : (root.busy ? "…" : "")
            foreground: root.foreground
            accent: root.accent
            font.family: root.fontFamily
            enabled: root.mode === "game"
            Keys.onReturnPressed: root.submit()
            Keys.onEnterPressed: root.submit()
            Keys.onUpPressed: root.recallHistory(-1)
            Keys.onDownPressed: root.recallHistory(1)
            Keys.onEscapePressed: root.close()
            Keys.onTabPressed: root.switchPanel(1)
          }
        }
      }
    }
  }
}
