import QtQuick
import qs.Commons
import qs.Ui
import "../Store.js" as Store
import "../Stats.js" as Stats
import "../Glyphs.js" as Glyphs

// One project on the track tab. The whole row is the start/stop button;
// only the sheet arrows on the right do something else.
BorderSurface {
  id: row

  property var project: null
  property var view: null

  readonly property var look: view.look
  readonly property bool running: view.active !== null && view.active.project === project.id
  readonly property bool sheets: project.mode === "sheets"
  readonly property real sheetSoFar: sheets ? view.sheetTotal(project, project.sheet) : 0
  readonly property real average: sheets ? Stats.averageBefore(Stats.sheets(view.doc.sessions, project.id, view.dsh), project.sheet) : 0
  readonly property real today: view.projectTotal(project, view.todayStart)
  readonly property bool hot: mouse.containsMouse

  implicitHeight: view.look.rowHeight
  radius: Style.cornerRadius
  color: running ? Style.selectedFillFor(look.fg, look.accent) : (hot ? Style.hoverFillFor(look.fg, look.accent) : "transparent")
  borderSpec: running ? Border.controlSpec("selected", look.fg, look.accent) : Border.none()

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: row.view.service.toggle(row.project.id)
  }

  Rectangle {
    id: stripe
    x: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(4)
    height: parent.height - Style.space(16)
    radius: width / 2
    color: row.look.projectColor(row.project)
  }

  Column {
    anchors.left: stripe.right
    anchors.leftMargin: Style.space(10)
    anchors.right: controls.left
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(3)

    Label {
      look: row.look
      width: parent.width
      text: row.project.name
      font.bold: row.running
    }

    Row {
      spacing: Style.space(8)
      width: parent.width

      // Progress against the average of the earlier sheets: a feel for
      // "how far in am I, compared to usual".
      Item {
        visible: row.sheets && row.average > 0
        width: Style.space(72)
        height: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter

        Rectangle {
          anchors.fill: parent
          radius: height / 2
          color: row.look.faint
        }

        Rectangle {
          width: parent.width * Math.min(1, row.sheetSoFar / Math.max(1, row.average))
          height: parent.height
          radius: height / 2
          color: row.look.projectColor(row.project)
        }
      }

      Label {
        look: row.look
        secondary: true
        anchors.verticalCenter: parent.verticalCenter
        text: {
          if (row.sheets) {
            var t = Store.duration(row.sheetSoFar) + " on this sheet"
            if (row.average > 0) t += " · avg " + Store.duration(row.average)
            return t
          }
          return "today " + Store.duration(row.today)
        }
      }
    }
  }

  Row {
    id: controls
    anchors.right: parent.right
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Button {
      visible: row.sheets
      iconText: Glyphs.previous
      foreground: row.look.fg
      fontFamily: row.look.font
      horizontalPadding: Style.space(6)
      enabled: row.project.sheet > 0
      opacity: enabled ? 1 : 0.35
      tooltipText: "Back to sheet " + (row.project.sheet - 1)
      onClicked: row.view.service.previousSheet(row.project.id)
    }

    Label {
      visible: row.sheets
      look: row.look
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(62)
      horizontalAlignment: Text.AlignHCenter
      text: "Sheet " + row.project.sheet
      font.bold: true
    }

    Button {
      visible: row.sheets
      iconText: Glyphs.next
      foreground: row.look.fg
      fontFamily: row.look.font
      horizontalPadding: Style.space(6)
      tooltipText: "Sheet " + row.project.sheet + " is done — next sheet"
      onClicked: row.view.service.nextSheet(row.project.id)
    }

    Item { width: Style.space(8); height: 1 }

    // Mirrors the row click, as a visible target for the stylus.
    Button {
      iconText: row.running ? Glyphs.stop : Glyphs.play
      iconSize: Style.font.iconLarge
      bordered: true
      selected: row.running
      foreground: row.look.fg
      fontFamily: row.look.font
      horizontalPadding: Style.space(10)
      tooltipText: row.running ? "Stop" : "Start"
      onClicked: row.view.service.toggle(row.project.id)
    }
  }
}
