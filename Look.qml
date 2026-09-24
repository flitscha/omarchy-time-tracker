import QtQuick
import qs.Commons
import "Palette.js" as Palette

// Colours and type shared by every view, derived from the bar's theme so
// the popup follows theme switches. Project colours come from Palette.js.
QtObject {
  id: look

  property var bar: null

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color muted: Qt.darker(fg, 1.45)
  readonly property color faint: Util.alpha(fg, 0.12)
  readonly property color grid: Util.alpha(fg, 0.08)
  readonly property color accent: Color.accent
  readonly property color surface: Color.popups.background
  readonly property string font: bar && bar.fontFamily ? bar.fontFamily : Style.font.family

  readonly property int gap: Style.space(8)
  readonly property int rowHeight: Style.space(44)

  function projectColor(project) {
    return Palette.color(project ? project.color : 0, surface)
  }

  function slotColor(slot) {
    return Palette.color(slot, surface)
  }

  // Sequential ramp for magnitudes (heatmaps): the theme accent, from barely
  // there to full strength.
  function ramp(fraction) {
    if (fraction <= 0) return "transparent"
    return Util.alpha(accent, 0.15 + 0.85 * Math.min(1, fraction))
  }
}
