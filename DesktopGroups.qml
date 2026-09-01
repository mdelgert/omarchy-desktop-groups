import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui

// Which desktop every monitor is showing, as one item: an icon and a number.
//
// A "desktop" is one workspace per monitor -- hypr/desktop-groups.lua owns the
// mapping and the SUPER+F1..Fn bindings; this is a view over it.
//
// Deliberately not a row of numbers. The stock workspace widget is already
// that, and a second row beside it reads as one run of digits carrying two
// different meanings. The icon says "this is a desktop, not a workspace"; the
// number says which one.
//
// Click opens the panel -- the settings and the explanation of how any of this
// works both live there, because SUPER+F1 is not discoverable on its own.
BarWidget {
  id: root
  moduleName: "io.github.mdelgert.desktop-groups"

  // Geometric, not a Nerd Font glyph: it renders in whatever the bar font is
  // and reads as "a grid of screens" at bar size.
  readonly property string icon: "▦"

  // ---- Settings
  //
  // These mirror setup() in hyprland.lua. The Lua side owns the real mapping;
  // the widget needs only enough to label the number.
  readonly property int desktopCount: {
    var n = parseInt(String(setting("desktops", 3)), 10)
    if (!isFinite(n)) n = 3
    return Math.max(1, Math.min(12, n))
  }

  // 0 means "follow the connected monitor count", matching the module default.
  readonly property int configuredSlots: {
    var n = parseInt(String(setting("slots", 0)), 10)
    if (!isFinite(n)) n = 0
    return Math.max(0, Math.min(12, n))
  }

  readonly property int slotCount: configuredSlots > 0
    ? configuredSlots
    : Math.max(1, Hyprland.monitors.values.length)

  readonly property string bindPrefix: String(setting("bindPrefix", "SUPER + F"))

  // The focused workspace id, read straight off the Hyprland event stream.
  //
  // Hyprland.focusedWorkspace lags here: switching to a desktop creates
  // workspaces the model has not seen, and it only catches up on its next
  // refresh, so the bar number visibly trails the screens. The events carry the
  // id already, so tracking it directly updates the instant the switch lands.
  // The binding below is the fallback for before the first event arrives.
  property int liveWorkspaceId: 0

  readonly property int focusedWorkspaceId: {
    if (liveWorkspaceId > 0) return liveWorkspaceId
    var workspace = Hyprland.focusedWorkspace
    return workspace && workspace.id > 0 ? workspace.id : 0
  }

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      var name = String(event.name)

      // workspacev2: "<id>,<name>"      focusedmonv2: "<monitor>,<id>"
      // The v2 forms carry the numeric id; the v1 forms carry only a name and
      // would need the same lookup that is lagging in the first place.
      if (name === "workspacev2") {
        var id = parseInt(String(event.data).split(",")[0], 10)
        if (isFinite(id) && id > 0) root.liveWorkspaceId = id
      } else if (name === "focusedmonv2") {
        var focused = parseInt(String(event.data).split(",")[1], 10)
        if (isFinite(focused) && focused > 0) root.liveWorkspaceId = focused
      }
    }
  }

  // The desktop that workspace belongs to, or 0 when it sits outside the scheme
  // -- a scratchpad (negative id), or a workspace past desktops * slots.
  //
  // Every bar shows the same number rather than its own monitor's, because the
  // desktops move as a unit. They only disagree if a workspace was switched on
  // one screen alone, and then the focused screen is the honest answer.
  readonly property int currentDesktop: {
    if (focusedWorkspaceId < 1) return 0

    var desktop = Math.floor((focusedWorkspaceId - 1) / slotCount) + 1
    return desktop >= 1 && desktop <= desktopCount ? desktop : 0
  }

  // Drive the Lua module rather than reimplementing anything: it already sorts
  // monitors by position and preserves focus. require() is cached in
  // package.loaded, so this reaches the instance hyprland.lua set up.
  function callModule(expression) {
    if (!root.bar) return
    root.bar.run("hyprctl eval " + Util.shellQuote(
      "require('hypr.desktop-groups')." + expression))
  }

  function switchTo(desktop) { callModule("switch(" + desktop + ")") }
  function setEnabled(on) { callModule("set_enabled(" + (on ? "true" : "false") + ")") }
  function setHideSpecial(on) { callModule("set_hide_special(" + (on ? "true" : "false") + ")") }

  // ---- Panel lifecycle. Bar.findPanelWidget requires open/close/opened here.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  // The panel reads desktopCount/currentDesktop straight off this widget, so
  // those stay live bindings rather than values copied at inject time.
  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

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
    target: "io.github.mdelgert.desktop-groups"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  // Nothing to show on a single screen: a "desktop" collapses to one workspace,
  // which SUPER+1..0 already switches between. The Lua module stands down under
  // the same condition, so the bar should not advertise a feature that is off.
  // Zero width as well as hidden, or the bar reserves an empty slot for it.
  readonly property bool applicable: Hyprland.monitors.values.length > 1

  visible: applicable
  implicitWidth: applicable ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar

    // The icon alone. The number sat next to the workspace widget's digits and
    // read as one more of them; the desktop is in the tooltip and the panel,
    // which is where you look when you actually want to know.
    text: root.icon

    tooltipText: root.currentDesktop > 0
      ? "Desktop " + root.currentDesktop + " of " + root.desktopCount
        + "  ·  " + root.bindPrefix + "1–" + root.bindPrefix + root.desktopCount
      : "Desktop groups  ·  click for settings"

    onPressed: function() { root.togglePanel() }
  }
}
