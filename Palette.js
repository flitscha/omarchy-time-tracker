.pragma library

// Project colours. Eight categorical slots in a fixed, colour-blind-checked
// order (adjacent pairs clear deutan/protan/tritan separation), with steps
// chosen per surface: the dark column for dark themes, the light column for
// light ones. The theme's own ANSI colours were tried first and failed that
// check (gruvbox green, cyan and yellow blur together), so project identity
// uses these fixed hues while all chrome keeps following the theme.

var NAMES = ["Blue", "Orange", "Aqua", "Yellow", "Magenta", "Green", "Violet", "Red"]

var DARK = ["#3987e5", "#d95926", "#199e70", "#c98500", "#d55181", "#008300", "#9085e9", "#e66767"]
var LIGHT = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#4a3aa7", "#e34948"]

function luminance(c) {
  return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
}

function isDark(background) {
  return luminance(background) < 0.5
}

function color(slot, background) {
  var list = background && !isDark(background) ? LIGHT : DARK
  var i = Math.max(0, Math.min(list.length - 1, Math.round(Number(slot)) || 0))
  return list[i]
}
