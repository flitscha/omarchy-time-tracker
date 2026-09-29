.pragma library
.import "Store.js" as Store

// A made-up semester for screenshots and for trying the stats tab without
// real data: `omarchy-shell timetracker demo on`. Seeded, so every run draws
// the same weeks. The service keeps demo data in memory only.

function rng(seed) {
  var a = seed >>> 0
  return function() {
    a = (a + 0x6d2b79f5) >>> 0
    var t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

function overlaps(sessions, start, end) {
  for (var i = 0; i < sessions.length; i++)
    if (sessions[i].start < end && sessions[i].end > start) return true
  return false
}

function generate(now) {
  var random = rng(20260924)
  var weeks = 10
  var today = new Date(now)
  var monday = new Date(today.getFullYear(), today.getMonth(), today.getDate() - ((today.getDay() + 6) % 7))
  var firstMonday = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() - 7 * (weeks - 1))

  var courses = [
    { id: "demo-opt", name: "Optimization", short: "Opt", mode: "sheets", color: 0, effort: 5.5, evening: 0.5 },
    { id: "demo-meas", name: "Measure Theory", short: "Meas", mode: "sheets", color: 1, effort: 7, evening: 0.3 },
    { id: "demo-num", name: "Numerical Analysis", short: "Num", mode: "sheets", color: 2, effort: 4, evening: 0.2 },
    { id: "demo-rice", name: "Linux ricing", short: "Rice", mode: "counter", color: 3, effort: 3, evening: 0.8 },
    { id: "demo-sem", name: "Seminar", short: "Sem", mode: "counter", color: 4, effort: 1.5, evening: 0.1, hidden: true }
  ]

  var doc = Store.emptyDocument()
  var sessions = []
  for (var c = 0; c < courses.length; c++) {
    var course = courses[c]
    for (var w = 0; w < weeks; w++) {
      // Sheets get harder mid-semester; the ricing budget drifts at random.
      var hardness = 0.7 + 0.6 * Math.sin(Math.PI * w / (weeks - 1)) + random() * 0.4
      var budget = course.effort * hardness * Store.HOUR
      var sheet = course.mode === "sheets" ? w + 1 : null
      var used = 0
      var guard = 0
      while (used < budget && guard++ < 12) {
        // Most of the work lands late in the week, right before the deadline.
        var dayOffset = Math.min(6, Math.floor(Math.pow(random(), 0.6) * 7))
        var eveningish = random() < course.evening
        var hour = eveningish ? 19 + random() * 4 : 9 + random() * 8
        var start = new Date(firstMonday.getFullYear(), firstMonday.getMonth(), firstMonday.getDate() + 7 * w + dayOffset,
          Math.floor(hour), Math.floor(random() * 4) * 15).getTime()
        var length = Math.min(budget - used, (30 + random() * 150) * Store.MINUTE)
        if (length < 15 * Store.MINUTE) break
        var end = start + length
        if (end > now - 2 * Store.HOUR || overlaps(sessions, start, end)) continue
        sessions.push({ id: "demo-s" + sessions.length, project: course.id, sheet: sheet, start: start, end: end,
          stop: random() < 0.15 ? "lock" : "manual" })
        used += length
      }
    }
    doc.projects.push({
      id: course.id, name: course.name, short: course.short, mode: course.mode,
      sheet: course.mode === "sheets" ? weeks : 1, color: course.color,
      visible: !course.hidden, created: firstMonday.getTime()
    })
  }
  sessions.sort(function(a, b) { return a.start - b.start })
  doc.sessions = sessions
  return Store.normalize(doc)
}
