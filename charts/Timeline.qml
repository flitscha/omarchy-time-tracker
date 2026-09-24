import QtQuick
import qs.Commons
import "../Store.js" as Store

// One lane per day, each session a block at its real time of day. Shows the
// rhythm: late starts, long evenings, the day before a deadline.
Item {
  id: root

  property var look: null
  property var lanes: []           // Stats.timeline()
  property var projectFor: function(id) { return null }
  property int dayStartHour: 4
  property var hovered: null
  property string hoveredDay: ""

  readonly property int labelWidth: Style.space(58)
  readonly property int totalWidth: Style.space(44)
  readonly property int laneHeight: Style.space(14)
  readonly property int laneGap: Style.space(4)
  readonly property int axisHeight: Style.space(16)
  readonly property real trackWidth: width - labelWidth - totalWidth
  readonly property string readout: {
    if (!hovered) return ""
    var p = projectFor(hovered.project)
    return hoveredDay + " · " + Store.timeOfDay(hovered.start) + "–" + Store.timeOfDay(hovered.end) + " · "
      + (p ? p.name : "?") + (hovered.sheet !== null && hovered.sheet !== undefined ? " " + hovered.sheet : "")
      + " · " + Store.duration(hovered.end - hovered.start)
  }

  implicitHeight: lanes.length * (laneHeight + laneGap) + axisHeight

  // Hour ticks, counted from the logical day start.
  Repeater {
    model: [0, 6, 12, 18, 24]

    Item {
      required property int modelData
      x: root.labelWidth + root.trackWidth * modelData / 24
      width: 1
      height: root.height

      Rectangle {
        width: 1
        height: root.height - root.axisHeight
        color: root.look.grid
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        textFormat: Text.PlainText
        text: Store.pad2((root.dayStartHour + modelData) % 24)
        color: root.look.muted
        font.family: root.look.font
        font.pixelSize: Style.font.caption
      }
    }
  }

  Repeater {
    model: root.lanes

    Item {
      id: lane
      required property var modelData
      required property int index
      readonly property string title: Qt.formatDate(new Date(modelData.start), "ddd d.M.")
      y: index * (root.laneHeight + root.laneGap)
      width: root.width
      height: root.laneHeight

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: lane.title
        color: lane.modelData.total > 0 ? root.look.fg : root.look.muted
        font.family: root.look.font
        font.pixelSize: Style.font.caption
      }

      Rectangle {
        x: root.labelWidth
        width: root.trackWidth
        height: parent.height
        radius: Style.space(2)
        color: root.look.grid
      }

      Repeater {
        model: lane.modelData.segments

        Rectangle {
          required property var modelData
          x: root.labelWidth + root.trackWidth * modelData.from
          width: Math.max(2, root.trackWidth * (modelData.to - modelData.from) - 1)
          height: lane.height
          radius: Style.space(2)
          color: {
            var p = root.projectFor(modelData.project)
            return p ? root.look.projectColor(p) : root.look.muted
          }
          opacity: root.hovered && root.hovered !== modelData ? 0.55 : 1

          MouseArea {
            anchors.fill: parent
            anchors.margins: -Style.space(2)
            hoverEnabled: true
            onEntered: { root.hovered = parent.modelData; root.hoveredDay = lane.title }
            onExited: if (root.hovered === parent.modelData) root.hovered = null
          }
        }
      }

      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: lane.modelData.total > 0 ? Store.duration(lane.modelData.total) : ""
        color: root.look.muted
        font.family: root.look.font
        font.pixelSize: Style.font.caption
      }
    }
  }
}
