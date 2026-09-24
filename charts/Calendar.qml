import QtQuick
import qs.Commons
import "../Store.js" as Store
import "../Stats.js" as Stats

// Contribution-style calendar: one square per day, weeks as columns, shade
// by hours worked.
Item {
  id: root

  property var look: null
  property var days: []          // Stats.dailySeries(), oldest first
  property int dayStartHour: 4
  property int hoverIndex: -1

  readonly property int labelWidth: Style.space(30)
  readonly property int monthHeight: Style.space(16)
  // Pad the front so the first column starts on a Monday.
  readonly property int lead: days.length ? Stats.weekday(days[0].start) : 0
  readonly property int weeks: Math.ceil((days.length + lead) / 7)
  readonly property real cell: weeks ? Math.min(Style.space(24), (width - labelWidth) / weeks) : 0
  readonly property real maxValue: Stats.maxOf(days, "total")
  readonly property string readout: hoverIndex >= 0 && hoverIndex < days.length
    ? Qt.formatDate(new Date(days[hoverIndex].start), "ddd d MMMM") + " · " + Store.duration(days[hoverIndex].total)
    : ""

  implicitHeight: monthHeight + cell * 7

  Repeater {
    model: [0, 2, 4]
    Text {
      required property int modelData
      y: root.monthHeight + modelData * root.cell + (root.cell - height) / 2
      textFormat: Text.PlainText
      text: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][modelData]
      color: root.look.muted
      font.family: root.look.font
      font.pixelSize: Style.font.caption
    }
  }

  Repeater {
    model: root.days

    Item {
      id: day
      required property var modelData
      required property int index
      readonly property int pos: index + root.lead
      // Label a column with its month when it holds the month's first Monday.
      readonly property bool monthStart: pos % 7 === 0 ? new Date(modelData.start).getDate() <= 7 : index === 0
      x: root.labelWidth + Math.floor(pos / 7) * root.cell
      y: root.monthHeight + (pos % 7) * root.cell
      width: root.cell
      height: root.cell

      Rectangle {
        anchors.fill: parent
        anchors.margins: Style.space(1.5)
        radius: Style.space(2)
        color: day.modelData.total > 0 ? root.look.ramp(day.modelData.total / root.maxValue) : root.look.grid
        border.width: root.hoverIndex === day.index ? 1 : 0
        border.color: root.look.fg
      }

      Text {
        visible: day.monthStart
        y: -root.monthHeight - (day.pos % 7) * root.cell
        textFormat: Text.PlainText
        text: Qt.formatDate(new Date(day.modelData.start), "MMM")
        color: root.look.muted
        font.family: root.look.font
        font.pixelSize: Style.font.caption
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: root.hoverIndex = day.index
        onExited: if (root.hoverIndex === day.index) root.hoverIndex = -1
      }
    }
  }
}
