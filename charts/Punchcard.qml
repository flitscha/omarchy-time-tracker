import QtQuick
import qs.Commons
import "../Store.js" as Store

// The namesake: weekday x hour of day, one dot per cell, dot area
// proportional to the time spent in that hour across the whole range.
Item {
  id: root

  property var look: null
  property var grid: []          // 7 x 24 ms, Monday first
  property int hoverDay: -1
  property int hoverHour: -1

  readonly property var dayNames: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
  readonly property int labelWidth: Style.space(34)
  readonly property int axisHeight: Style.space(16)
  readonly property real cell: (width - labelWidth) / 24
  readonly property real rowHeight: Math.min(cell, Style.space(22))
  readonly property real maxValue: {
    var m = 0
    for (var d = 0; d < grid.length; d++) for (var h = 0; h < 24; h++) m = Math.max(m, grid[d][h])
    return m > 0 ? m : 1
  }
  readonly property string readout: hoverDay >= 0
    ? dayNames[hoverDay] + " " + Store.pad2(hoverHour) + ":00–" + Store.pad2((hoverHour + 1) % 24) + ":00 · "
      + Store.duration(grid[hoverDay][hoverHour]) + " in total"
    : ""

  implicitHeight: rowHeight * 7 + axisHeight

  Repeater {
    model: 7

    Item {
      id: dayRow
      required property int index
      y: index * root.rowHeight
      width: root.width
      height: root.rowHeight

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.dayNames[dayRow.index]
        color: root.hoverDay === dayRow.index ? root.look.fg : root.look.muted
        font.family: root.look.font
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: 24

        Item {
          id: cellItem
          required property int index
          readonly property real value: root.grid.length ? root.grid[dayRow.index][index] : 0
          x: root.labelWidth + index * root.cell
          width: root.cell
          height: root.rowHeight

          Rectangle {
            anchors.centerIn: parent
            readonly property real full: Math.min(root.cell, root.rowHeight) - Style.space(3)
            // Area, not diameter, tracks the value.
            width: cellItem.value > 0 ? Math.max(Style.space(3), full * Math.sqrt(cellItem.value / root.maxValue)) : Style.space(2)
            height: width
            radius: width / 2
            color: cellItem.value > 0 ? root.look.accent : root.look.faint
            opacity: cellItem.value > 0 ? 0.35 + 0.65 * Math.sqrt(cellItem.value / root.maxValue) : 1
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: { root.hoverDay = dayRow.index; root.hoverHour = cellItem.index }
            onExited: if (root.hoverDay === dayRow.index && root.hoverHour === cellItem.index) root.hoverDay = -1
          }
        }
      }
    }
  }

  Repeater {
    model: [0, 3, 6, 9, 12, 15, 18, 21]

    Text {
      required property int modelData
      x: root.labelWidth + modelData * root.cell
      y: 7 * root.rowHeight + Style.space(2)
      textFormat: Text.PlainText
      text: Store.pad2(modelData)
      color: root.look.muted
      font.family: root.look.font
      font.pixelSize: Style.font.caption
    }
  }
}
