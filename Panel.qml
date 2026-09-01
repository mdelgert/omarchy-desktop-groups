import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Settings and instructions behind the bar icon.
//
// This is where the feature explains itself. SUPER+F1 is not discoverable --
// nothing on screen implies it -- so the keys are spelled out here alongside
// the two switches worth having.
//
// DesktopGroups.qml owns the bar icon and hands this panel the button to anchor
// against. Desktop state is read live off that host; the two toggles come from
// the module's state file, since only Lua knows whether it is currently on.
Panel {
  id: root
  moduleName: "io.github.mdelgert.desktop-groups"
  ipcTarget: "io.github.mdelgert.desktop-groups"
  // The host widget owns the single IpcHandler this target allows.
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  // The bar tracks the widget mounted in its slot, not this nested panel.
  readonly property var barIdentity: hostWidget || root

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(contentForeground, 1.4)

  // Live off the host widget, so the panel tracks a desktop switch made while
  // it is open -- including one made from the keyboard.
  readonly property int desktopCount: hostWidget ? hostWidget.desktopCount : 3
  readonly property int currentDesktop: hostWidget ? hostWidget.currentDesktop : 0
  readonly property int slotCount: hostWidget ? hostWidget.slotCount : 1
  readonly property string bindPrefix: hostWidget ? hostWidget.bindPrefix : "SUPER + F"

  // Mirrors of the module's persisted state. Optimistically flipped on click so
  // the switch responds immediately, then re-read from the file on next open.
  property bool moduleEnabled: true
  property bool hideSpecial: true

  // The workspaces a desktop owns: desktop 2 on four monitors is 5-8. Shown
  // because the bar deliberately hides these numbers, and this is the one place
  // the mapping should be legible.
  function workspaceRange(desktop) {
    var first = (desktop - 1) * root.slotCount + 1
    var last = first + root.slotCount - 1
    return root.slotCount > 1 ? first + "–" + last : String(first)
  }

  function applyState(text) {
    var enabled = true
    var hide = true

    var lines = String(text).split("\n")
    for (var i = 0; i < lines.length; i++) {
      var parts = lines[i].trim().split("=")
      if (parts.length !== 2) continue
      if (parts[0] === "enabled") enabled = parts[1] === "1"
      else if (parts[0] === "hide_special") hide = parts[1] === "1"
    }

    root.moduleEnabled = enabled
    root.hideSpecial = hide
  }

  // Re-read on open rather than polling: nothing else writes this file, and a
  // closed panel has no reason to watch it.
  onOpenedChanged: if (opened) {
    stateProc.command = ["sh", "-c",
      "cat \"${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/desktop-groups.conf\" 2>/dev/null"]
    stateProc.running = true
  }

  Process {
    id: stateProc
    running: false
    command: []
    stdout: StdioCollector { id: stateOut; waitForEnd: true }
    // A missing file is the normal first-run case, not an error: the defaults
    // above already describe a freshly installed module.
    onExited: root.applyState(stateOut.text || "")
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(330))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: root.close()

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "DESKTOP GROUPS"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.currentDesktop > 0
              ? "On desktop " + root.currentDesktop + " of " + root.desktopCount
                + " — workspaces " + root.workspaceRange(root.currentDesktop) + "."
              : "The focused screen is on a workspace outside these desktops."
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }

          PanelSeparator { foreground: root.contentForeground }

          Toggle {
            width: parent.width
            label: "Desktop groups"
            description: root.bindPrefix + "1 … " + root.bindPrefix + root.desktopCount
              + " switch every monitor at once. Turning this off returns Hyprland "
              + "to its own workspace placement. No window is moved."
            checked: root.moduleEnabled
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: {
              root.moduleEnabled = !root.moduleEnabled
              if (root.hostWidget) root.hostWidget.setEnabled(root.moduleEnabled)
            }
          }

          Toggle {
            width: parent.width
            label: "Hide scratchpad on switch"
            description: "Put the SUPER+S scratchpad away when the workspace "
              + "changes. A desktop switch changes every monitor at once, so this "
              + "is far more noticeable here than on a single screen."
            checked: root.hideSpecial
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: {
              root.hideSpecial = !root.hideSpecial
              if (root.hostWidget) root.hostWidget.setHideSpecial(root.hideSpecial)
            }
          }

          PanelSeparator { foreground: root.contentForeground }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "A desktop is one workspace per monitor. Switching moves every "
              + "screen together, like Win+Ctrl+Arrow on Windows. Monitors are "
              + "ordered left to right by position. Your SUPER+1…0 workspace keys "
              + "are unchanged."
            color: root.dim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
