import QtQuick
import qs.Commons
import "../Store.js" as Store

// Where the time went: one 100% bar split by project, and a legend that
// carries the names and numbers so colour is never the only cue.
Column {
  id: root

  property var look: null
  property var entries: []   // [{ project, value }] sorted, largest first
  property int hoverIndex: -1

  readonly property real sum: {
    var s = 0
    for (var i = 0; i < entries.length; i++) s += entries[i].value
    return s > 0 ? s : 1
  }
  readonly property string readout: hoverIndex >= 0
    ? entries[hoverIndex].project.name + " · " + Store.duration(entries[hoverIndex].value)
      + " · " + Math.round(100 * entries[hoverIndex].value / sum) + "%"
    : ""

  spacing: Style.space(8)

  Item {
    width: parent.width
    height: Style.space(14)

    Repeater {
      model: root.entries

      Rectangle {
        required property var modelData
        required property int index
        readonly property real before: {
          var s = 0
          for (var i = 0; i < index; i++) s += root.entries[i].value
          return s
        }
        x: root.width * before / root.sum
        width: Math.max(1, root.width * modelData.value / root.sum - (index < root.entries.length - 1 ? 2 : 0))
        height: parent.height
        radius: Style.space(2)
        color: root.look.projectColor(modelData.project)
        opacity: root.hoverIndex >= 0 && root.hoverIndex !== index ? 0.45 : 1

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          onEntered: root.hoverIndex = parent.index
          onExited: if (root.hoverIndex === parent.index) root.hoverIndex = -1
        }
      }
    }
  }

  Flow {
    width: parent.width
    spacing: Style.space(14)

    Repeater {
      model: root.entries

      Row {
        required property var modelData
        required property int index
        spacing: Style.space(6)

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(8)
          height: width
          radius: width / 2
          color: root.look.projectColor(modelData.project)
        }

        Text {
          textFormat: Text.PlainText
          text: modelData.project.name + "  " + Store.duration(modelData.value)
            + "  " + Math.round(100 * modelData.value / root.sum) + "%"
          color: root.hoverIndex === index ? root.look.fg : root.look.muted
          font.family: root.look.font
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
