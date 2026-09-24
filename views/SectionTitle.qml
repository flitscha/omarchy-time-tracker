import QtQuick
import qs.Commons

// Small-caps section heading with an optional readout on the right. Charts
// put their hover readout there, so the numbers of whatever the pointer is
// on appear in one fixed place instead of a tooltip that covers the marks.
Item {
  id: root

  property var look: null
  property string text: ""
  property string detail: ""

  width: parent ? parent.width : 0
  implicitHeight: Math.max(title.implicitHeight, readout.implicitHeight)

  Text {
    id: title
    textFormat: Text.PlainText
    text: root.text.toUpperCase()
    color: root.look ? root.look.muted : Color.foreground
    font.family: root.look ? root.look.font : Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1
  }

  Text {
    id: readout
    anchors.right: parent.right
    anchors.left: title.right
    anchors.leftMargin: Style.space(12)
    horizontalAlignment: Text.AlignRight
    textFormat: Text.PlainText
    text: root.detail
    color: root.look ? root.look.fg : Color.foreground
    font.family: root.look ? root.look.font : Style.font.family
    font.pixelSize: Style.font.caption
    elide: Text.ElideLeft
  }
}
