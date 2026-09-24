import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Glyphs.js" as Glyphs
import "views"

// The popup under the bar pill: four tabs over one service.
//
// Keys: 1-4 or Tab switch tabs, Esc closes. Everything else is meant for
// mouse and pen; the keyboard is only needed to type names.
KeyboardPanel {
  id: panel

  property var service: null
  property string tab: "track"

  readonly property var tabs: [
    { key: "track", label: "Track", icon: Glyphs.timerIdle },
    { key: "log", label: "Log", icon: Glyphs.history },
    { key: "stats", label: "Stats", icon: Glyphs.chart },
    { key: "projects", label: "Projects", icon: Glyphs.list }
  ]

  // A focused text field needs every key, including Esc and Tab.
  readonly property bool editing: currentView !== null && currentView.editing === true
  readonly property var currentView: viewLoader.item

  signal closeRequested()

  function switchTab(direction) {
    var i = 0
    for (var k = 0; k < tabs.length; k++) if (tabs[k].key === tab) i = k
    tab = tabs[(i + direction + tabs.length) % tabs.length].key
  }

  // KeyboardPanel's default property only takes visual items, so the
  // non-visual pieces hang off properties.
  readonly property Look theme: Look { bar: panel.bar }

  focusTarget: keys
  contentWidth: panel.fittedContentWidth(Style.space(600))
  contentHeight: panel.fittedContentHeight(header.height + Style.space(10) + viewLoader.implicitHeight, Style.space(660))

  onOpenChanged: if (open && currentView && typeof currentView.refresh === "function") currentView.refresh()
  // Closing a form must hand the keys back, or 1-4 and Esc stop working.
  onEditingChanged: if (!editing) keys.forceActiveFocus()
  onTabChanged: keys.forceActiveFocus()

  PanelKeyCatcher {
    id: keys
    anchors.fill: parent
    blocked: panel.editing
    onCloseRequested: panel.close()
    onTabRequested: function(direction) { panel.switchTab(direction) }
    onTextKey: function(t) {
      var n = parseInt(t)
      if (n >= 1 && n <= panel.tabs.length) panel.tab = panel.tabs[n - 1].key
    }

    Item {
      id: header
      width: parent.width
      height: tabRow.height

      Row {
        id: tabRow
        spacing: Style.space(4)

        Repeater {
          model: panel.tabs

          Button {
            required property var modelData
            text: modelData.label
            iconText: modelData.icon
            selected: panel.tab === modelData.key
            foreground: panel.theme.fg
            fontFamily: panel.theme.font
            onClicked: panel.tab = modelData.key
          }
        }
      }

      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: panel.service !== null && (panel.service.demo || panel.service.loadError !== "")
        text: panel.service && panel.service.loadError ? "data.json unreadable" : "demo data"
        color: panel.service && panel.service.loadError ? Color.urgent : panel.theme.muted
        font.family: panel.theme.font
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }

    Flickable {
      id: scroller
      anchors.top: header.bottom
      anchors.topMargin: Style.space(10)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      contentWidth: width
      contentHeight: viewLoader.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Loader {
        id: viewLoader
        width: scroller.width
        active: panel.service !== null && panel.visible
        sourceComponent: {
          if (panel.tab === "log") return panel.logView
          if (panel.tab === "stats") return panel.statsView
          if (panel.tab === "projects") return panel.projectsView
          return panel.trackView
        }
        onLoaded: scroller.contentY = 0
      }
    }
  }

  property Component trackView: Component {
    TrackView {
      service: panel.service
      look: panel.theme
      onNavigate: function(target) { panel.tab = target }
    }
  }

  property Component logView: Component {
    LogView { service: panel.service; look: panel.theme }
  }

  property Component statsView: Component {
    StatsView { service: panel.service; look: panel.theme }
  }

  property Component projectsView: Component {
    ProjectsView { service: panel.service; look: panel.theme }
  }
}
