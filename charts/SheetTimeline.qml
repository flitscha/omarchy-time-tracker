import QtQuick
import qs.Commons
import "../Store.js" as Store
import "../Stats.js" as Stats

// When each sheet was worked on: one row per sheet, one mark per day that
// had time on it, mark size by hours. A healthy week is a tight cluster;
// the night before the deadline is a single fat dot at the right edge.
Item {
  id: root

  property var look: null
  property var project: null
  property var sessions: []       // already filtered to this project and range
  property real from: 0
  property real to: 0
  property int dayStartHour: 4
  property var hovered: null

  readonly property int labelWidth: Style.space(34)
  readonly property int rowHeight: Style.space(17)
  readonly property int axisHeight: Style.space(16)

  // [{ sheet, days: [{ start, total }] }]
  readonly property var rows: {
    var bySheet = {}
    for (var i = 0; i < sessions.length; i++) {
      var s = sessions[i]
      if (s.sheet === null || s.sheet === undefined) continue
      var m = bySheet[s.sheet] || (bySheet[s.sheet] = {})
      Stats.eachDayPiece(s, dayStartHour, function(day, a, b) { m[day] = (m[day] || 0) + b - a })
    }
    var out = []
    for (var key in bySheet) {
      var days = []
      for (var d in bySheet[key]) days.push({ start: Number(d), total: bySheet[key][d] })
      days.sort(function(a, b) { return a.start - b.start })
      out.push({ sheet: Number(key), days: days })
    }
    out.sort(function(a, b) { return a.sheet - b.sheet })
    return out
  }
  readonly property real firstDay: Stats.dayStartOf(from, dayStartHour)
  readonly property int dayCount: Math.max(1, Math.round((Stats.dayStartOf(to - 1, dayStartHour) - firstDay) / Store.DAY) + 1)
  readonly property real step: (width - labelWidth) / dayCount
  readonly property real maxDay: {
    var m = 0
    for (var i = 0; i < rows.length; i++) for (var j = 0; j < rows[i].days.length; j++) m = Math.max(m, rows[i].days[j].total)
    return m > 0 ? m : 1
  }
  readonly property string readout: hovered
    ? "Sheet " + hovered.sheet + " · " + Qt.formatDate(new Date(hovered.start), "ddd d MMM") + " · " + Store.duration(hovered.total)
    : ""

  function xFor(dayStart) {
    return labelWidth + step * Math.round((dayStart - firstDay) / Store.DAY) + step / 2
  }

  implicitHeight: rows.length * rowHeight + axisHeight

  // Week separators, so "which week" is readable without dates on every dot.
  Repeater {
    model: Math.ceil(root.dayCount / 7) + 1

    Rectangle {
      required property int index
      readonly property real monday: Stats.addDays(Stats.weekStartOf(root.firstDay, root.dayStartHour), index * 7, root.dayStartHour)
      visible: monday >= root.firstDay
      x: root.xFor(monday) - root.step / 2
      width: 1
      height: root.rows.length * root.rowHeight
      color: root.look.grid
    }
  }

  Repeater {
    model: root.rows

    Item {
      id: row
      required property var modelData
      required property int index
      y: index * root.rowHeight
      width: root.width
      height: root.rowHeight

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: row.modelData.sheet
        color: root.look.muted
        font.family: root.look.font
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: row.modelData.days

        Rectangle {
          id: dot
          required property var modelData
          readonly property real full: root.rowHeight - Style.space(3)
          x: root.xFor(modelData.start) - width / 2
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(Style.space(4), full * Math.sqrt(modelData.total / root.maxDay))
          height: width
          radius: width / 2
          color: root.look.projectColor(root.project)
          opacity: root.hovered && root.hovered.start === modelData.start && root.hovered.sheet === row.modelData.sheet ? 1 : 0.8

          MouseArea {
            anchors.fill: parent
            anchors.margins: -Style.space(3)
            hoverEnabled: true
            onEntered: root.hovered = { sheet: row.modelData.sheet, start: dot.modelData.start, total: dot.modelData.total }
            onExited: root.hovered = null
          }
        }
      }
    }
  }

  Text {
    y: root.rows.length * root.rowHeight + Style.space(2)
    x: root.labelWidth
    textFormat: Text.PlainText
    text: Qt.formatDate(new Date(root.firstDay), "d MMM")
    color: root.look.muted
    font.family: root.look.font
    font.pixelSize: Style.font.caption
  }

  Text {
    y: root.rows.length * root.rowHeight + Style.space(2)
    anchors.right: parent.right
    textFormat: Text.PlainText
    text: Qt.formatDate(new Date(root.to - 1), "d MMM")
    color: root.look.muted
    font.family: root.look.font
    font.pixelSize: Style.font.caption
  }
}
