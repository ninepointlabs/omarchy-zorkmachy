import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Games.js" as Games

// The bar chip: a console glyph plus, while a Zork is open, which one and
// your score. Click to open the panel.
BarWidget {
  id: root
  moduleName: "ninepointlabs.zorkmachy"

  readonly property var service: panelLoader.item ? panelLoader.item.service : null
  readonly property int revision: service ? service.revision : 0
  readonly property string current: service && revision >= 0 ? service.current : ""
  readonly property var game: service && revision >= 0 ? service.currentGame : null
  readonly property var meta: current !== "" ? Games.gameByKey(current) : null
  readonly property bool showStatus: setting("showStatus", true) === true

  readonly property string labelText: {
    if (!game || !meta) return ""
    return "Zork " + meta.numeral + " · " + game.score
  }

  readonly property color chipColor: {
    if (!bar) return Color.foreground
    if (game && meta) return bar.barForeground
    return Qt.darker(bar.barForeground, 1.5)
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function anyOpened() {
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : [root]
    for (var i = 0; i < items.length; i++) if (items[i] && items[i].opened === true) return true
    return false
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  readonly property real openPanelIndicatorWidth: button.width
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "ninepointlabs.zorkmachy"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function isOpen(): string { return root.anyOpened() ? "true" : "false" }
    function status(): string {
      if (!root.service) return "{}"
      var g = root.service.currentGame
      return JSON.stringify({ game: root.service.current, phase: root.service.phase, ready: root.service.ready, interpreter: root.service.interpreterAvailable, room: g ? g.room : "", score: g ? g.score : 0, moves: g ? g.moves : 0, lines: g ? g.transcript.length : 0 })
    }
    function select(key: string): string { if (!root.service) return "no service"; root.service.selectGame(key); return "ok" }
    function picker(): string { if (!root.service) return "no service"; root.service.showPicker(); return "ok" }
    function send(command: string): string { return root.service && root.service.send(command) ? "ok" : "busy" }
    function tail(): string {
      var g = root.service ? root.service.currentGame : null
      if (!g) return ""
      var out = []
      for (var i = Math.max(0, g.transcript.length - 3); i < g.transcript.length; i++) out.push((g.transcript[i].k === "in" ? "> " : "") + g.transcript[i].t)
      return out.join("\n")
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : Math.round(chipRow.implicitWidth + Style.spaceReal(horizontalMargin) * 2)
    fixedHeight: root.vertical ? Style.bar.iconSlot : -1
    horizontalMargin: root.labelText !== "" && root.showStatus && !root.vertical ? 7 : 6
    tooltipText: root.game && root.meta ? "Zorkmachy · " + root.meta.title + (root.game.room !== "" ? " · " + root.game.room : "") : "Zorkmachy"

    onPressed: function(b) { root.togglePanel() }

    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: Style.space(6)

      OpticalGlyph {
        width: Style.bar.iconCanvas + Style.space(2)
        height: width
        anchors.verticalCenter: parent.verticalCenter
        text: "󰆍"
        fontFamily: button.fontFamily
        fontSize: Style.bar.iconFont
        color: root.chipColor
      }

      Text {
        visible: root.showStatus && !root.vertical && root.labelText !== ""
        textFormat: Text.PlainText
        text: root.labelText
        color: root.chipColor
        font.family: button.fontFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }
}
