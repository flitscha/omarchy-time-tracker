import QtQuick
import qs.Commons
import "../Stats.js" as Stats
import "../Store.js" as Store

// Vertical bars on an hours axis, optionally stacked by project, with an
// optional dashed reference line (the average on the sheets chart).
//
// series: [{ label, parts: [{ id, value }], readout }]
//   `label` goes under the bar (thinned out when crowded), `readout` is what
//   the section header shows while the pointer is on the bar.
Item {
  id: root

  property var look: null
  property var series: []
  property var colorFor: function(id) { return root.look.accent }
  property real reference: 0
  property string referenceLabel: ""
  property int hoverIndex: -1
  readonly property string readout: hoverIndex >= 0 && hoverIndex < series.length ? series[hoverIndex].readout : ""

  readonly property int axisWidth: Style.space(34)
  readonly property int labelHeight: Style.space(16)
  readonly property int plotHeight: height - labelHeight
  readonly property real maxValue: {
    var m = reference
    for (var i = 0; i < series.length; i++) m = Math.max(m, totalOf(series[i]))
    return Stats.niceHours(m)
  }
  readonly property int endPadding: Style.space(8)
  readonly property real slot: series.length ? (width - axisWidth - endPadding) / series.length : 0
  readonly property real barWidth: Math.max(2, Math.min(Style.space(28), slot - Math.max(2, slot * 0.28)))
  readonly property int labelEvery: Math.max(1, Math.ceil(Style.space(34) / Math.max(1, slot)))

  implicitHeight: Style.space(150)

  function totalOf(entry) {
    var sum = 0
    for (var i = 0; i < entry.parts.length; i++) sum += entry.parts[i].value
    return sum
  }

  function yFor(value) {
    return plotHeight - plotHeight * value / maxValue
  }

  // Gridlines at 0, half and the top of the nice axis.
  Repeater {
    model: [0, 0.5, 1]

    Item {
      required property real modelData
      y: root.yFor(root.maxValue * modelData)
      width: root.width
      height: 1

      Rectangle {
        x: root.axisWidth
        width: parent.width - root.axisWidth
        height: 1
        color: modelData === 0 ? root.look.faint : root.look.grid
      }

      Text {
        anchors.right: parent.left
        anchors.rightMargin: -root.axisWidth + Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: Store.hours(root.maxValue * modelData) + "h"
        color: root.look.muted
        font.family: root.look.font
        font.pixelSize: Style.font.caption
      }
    }
  }

  Repeater {
    model: root.series

    Item {
      id: bar
      required property var modelData
      required property int index

      readonly property var segments: {
        var out = []
        var base = 0
        for (var i = 0; i < modelData.parts.length; i++) {
          var v = modelData.parts[i].value
          if (v <= 0) continue
          out.push({ id: modelData.parts[i].id, from: base, to: base + v })
          base += v
        }
        return out
      }

      x: root.axisWidth + index * root.slot
      width: root.slot
      height: root.height

      Rectangle {
        anchors.fill: parent
        anchors.bottomMargin: root.labelHeight
        color: root.hoverIndex === bar.index ? root.look.grid : "transparent"
      }

      Repeater {
        model: bar.segments

        Rectangle {
          required property var modelData
          required property int index
          readonly property bool isTop: index === bar.segments.length - 1
          x: (bar.width - root.barWidth) / 2
          width: root.barWidth
          y: root.yFor(modelData.to)
          // 2px of surface between stacked segments.
          height: Math.max(1, root.yFor(modelData.from) - root.yFor(modelData.to) - (index > 0 ? 2 : 0))
          color: root.colorFor(modelData.id)
          topLeftRadius: isTop ? Math.min(Style.space(4), root.barWidth / 2) : 0
          topRightRadius: topLeftRadius
        }
      }

      Text {
        visible: bar.index % root.labelEvery === (root.series.length - 1) % root.labelEvery
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        textFormat: Text.PlainText
        text: bar.modelData.label
        color: root.hoverIndex === bar.index ? root.look.fg : root.look.muted
        font.family: root.look.font
        font.pixelSize: Style.font.caption
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: root.hoverIndex = bar.index
        onExited: if (root.hoverIndex === bar.index) root.hoverIndex = -1
      }
    }
  }

  // Reference line, dashed so it never reads as a bar edge.
  Row {
    visible: root.reference > 0
    x: root.axisWidth
    y: root.yFor(root.reference)
    spacing: Style.space(3)

    Repeater {
      model: Math.max(0, Math.floor((root.width - root.axisWidth) / Style.space(7)))
      Rectangle { width: Style.space(4); height: Math.max(1, Style.space(1.5)); color: root.look.fg; opacity: 0.7 }
    }
  }

  Text {
    visible: root.reference > 0 && root.referenceLabel !== ""
    anchors.right: parent.right
    y: root.yFor(root.reference) - height - Style.space(1)
    textFormat: Text.PlainText
    text: root.referenceLabel
    color: root.look.fg
    font.family: root.look.font
    font.pixelSize: Style.font.caption
  }
}
