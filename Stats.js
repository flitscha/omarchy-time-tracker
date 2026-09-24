.pragma library
.import "Store.js" as Store

// Aggregations for the stats tab. Pure functions over session lists, so the
// popup can recompute everything on each redraw and the tests can run them
// under node.
//
// "Day" means a logical day that starts at settings.dayStartHour (04:00 by
// default): an evening that runs past midnight still counts towards the day
// it started on. Hour-of-day charts use the real clock instead.

var HOUR = Store.HOUR
var DAY = Store.DAY

// ---- Calendar helpers -------------------------------------------------------

function dayStartOf(ms, dsh) {
  var d = new Date(ms)
  var start = new Date(d.getFullYear(), d.getMonth(), d.getDate(), dsh)
  if (start.getTime() > ms) start = new Date(d.getFullYear(), d.getMonth(), d.getDate() - 1, dsh)
  return start.getTime()
}

function addDays(dayStartMs, n, dsh) {
  var d = new Date(dayStartMs)
  return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n, dsh).getTime()
}

function dayKey(dayStartMs) {
  var d = new Date(dayStartMs)
  return d.getFullYear() + "-" + Store.pad2(d.getMonth() + 1) + "-" + Store.pad2(d.getDate())
}

// Monday = 0 ... Sunday = 6.
function weekday(dayStartMs) {
  return (new Date(dayStartMs).getDay() + 6) % 7
}

function weekStartOf(ms, dsh) {
  var day = dayStartOf(ms, dsh)
  return addDays(day, -weekday(day), dsh)
}

function monthStartOf(ms, dsh) {
  var d = new Date(dayStartOf(ms, dsh))
  return new Date(d.getFullYear(), d.getMonth(), 1, dsh).getTime()
}

// ---- Selection --------------------------------------------------------------

// The stored sessions plus the running one, cut off at `now`.
function withActive(sessions, active, now) {
  if (!active || now <= active.start) return sessions
  var list = sessions.slice()
  list.push({ id: "active", project: active.project, sheet: active.sheet, start: active.start, end: now, stop: "running" })
  return list
}

function filterProject(sessions, projectId) {
  if (!projectId) return sessions
  return sessions.filter(function(s) { return s.project === projectId })
}

// Sessions overlapping [from, to), trimmed to that window.
function clip(sessions, from, to) {
  var out = []
  for (var i = 0; i < sessions.length; i++) {
    var s = sessions[i]
    if (s.end <= from || s.start >= to) continue
    if (s.start >= from && s.end <= to) { out.push(s); continue }
    out.push(Object.assign({}, s, { start: Math.max(s.start, from), end: Math.min(s.end, to) }))
  }
  return out
}

function total(sessions) {
  var sum = 0
  for (var i = 0; i < sessions.length; i++) sum += sessions[i].end - sessions[i].start
  return sum
}

function byProject(sessions) {
  var out = {}
  for (var i = 0; i < sessions.length; i++) {
    var s = sessions[i]
    out[s.project] = (out[s.project] || 0) + s.end - s.start
  }
  return out
}

// Walks a session in pieces that never cross a logical day boundary.
function eachDayPiece(session, dsh, fn) {
  var t = session.start
  while (t < session.end) {
    var day = dayStartOf(t, dsh)
    var next = addDays(day, 1, dsh)
    var end = Math.min(next, session.end)
    fn(day, t, end)
    t = end
  }
}

// dayKey -> { start, total, projects: { id: ms } }
function perDay(sessions, dsh) {
  var out = {}
  for (var i = 0; i < sessions.length; i++) {
    var s = sessions[i]
    eachDayPiece(s, dsh, function(day, from, to) {
      var key = dayKey(day)
      var entry = out[key] || (out[key] = { start: day, total: 0, projects: {} })
      entry.total += to - from
      entry.projects[s.project] = (entry.projects[s.project] || 0) + to - from
    })
  }
  return out
}

// `days` consecutive days ending with the one containing `now`, oldest first.
function dailySeries(sessions, days, now, dsh) {
  var map = perDay(sessions, dsh)
  var today = dayStartOf(now, dsh)
  var out = []
  for (var i = days - 1; i >= 0; i--) {
    var day = addDays(today, -i, dsh)
    var entry = map[dayKey(day)]
    out.push({ key: dayKey(day), start: day, total: entry ? entry.total : 0, projects: entry ? entry.projects : {} })
  }
  return out
}

function weeklySeries(sessions, weeks, now, dsh) {
  var thisWeek = weekStartOf(now, dsh)
  var out = []
  for (var i = weeks - 1; i >= 0; i--) {
    var from = addDays(thisWeek, -7 * i, dsh)
    var to = addDays(from, 7, dsh)
    var part = clip(sessions, from, to)
    out.push({ start: from, total: total(part), projects: byProject(part) })
  }
  return out
}

// 7 x 24 matrix of milliseconds, Monday first, real clock hours.
function punchcard(sessions) {
  var grid = []
  for (var d = 0; d < 7; d++) {
    var row = []
    for (var h = 0; h < 24; h++) row.push(0)
    grid.push(row)
  }
  for (var i = 0; i < sessions.length; i++) {
    var t = sessions[i].start
    var end = sessions[i].end
    while (t < end) {
      var date = new Date(t)
      var next = new Date(date.getFullYear(), date.getMonth(), date.getDate(), date.getHours() + 1).getTime()
      var stop = Math.min(next, end)
      grid[(date.getDay() + 6) % 7][date.getHours()] += stop - t
      t = stop
    }
  }
  return grid
}

// One lane per day, oldest first; segments as fractions of the logical day.
function timeline(sessions, days, now, dsh) {
  var today = dayStartOf(now, dsh)
  var first = addDays(today, -(days - 1), dsh)
  var lanes = []
  var index = {}
  for (var i = 0; i < days; i++) {
    var day = addDays(first, i, dsh)
    index[dayKey(day)] = lanes.length
    lanes.push({ key: dayKey(day), start: day, length: addDays(day, 1, dsh) - day, total: 0, segments: [] })
  }
  var part = clip(sessions, first, addDays(today, 1, dsh))
  for (var j = 0; j < part.length; j++) {
    var s = part[j]
    eachDayPiece(s, dsh, function(day, from, to) {
      var lane = lanes[index[dayKey(day)]]
      if (!lane) return
      lane.total += to - from
      lane.segments.push({ from: (from - day) / lane.length, to: (to - day) / lane.length, project: s.project, sheet: s.sheet, start: from, end: to })
    })
  }
  return lanes
}

// ---- Sheets -----------------------------------------------------------------

// Per sheet of one project: time, sessions, first and last touch, and on how
// many different days it was worked on. Sorted by sheet number.
function sheets(sessions, projectId, dsh) {
  var map = {}
  for (var i = 0; i < sessions.length; i++) {
    var s = sessions[i]
    if (s.project !== projectId || s.sheet === null || s.sheet === undefined) continue
    var entry = map[s.sheet] || (map[s.sheet] = { sheet: s.sheet, total: 0, count: 0, first: s.start, last: s.end, dayKeys: {} })
    entry.total += s.end - s.start
    entry.count++
    entry.first = Math.min(entry.first, s.start)
    entry.last = Math.max(entry.last, s.end)
    eachDayPiece(s, dsh, function(day) { entry.dayKeys[dayKey(day)] = true })
  }
  var out = []
  for (var key in map) {
    var e = map[key]
    e.days = Object.keys(e.dayKeys).length
    delete e.dayKeys
    out.push(e)
  }
  out.sort(function(a, b) { return a.sheet - b.sheet })
  return out
}

// Average time of the sheets before `sheet`, the yardstick for the current
// one. Zero when there is no finished sheet yet.
function averageBefore(sheetList, sheet) {
  var sum = 0
  var n = 0
  for (var i = 0; i < sheetList.length; i++) {
    if (sheetList[i].sheet >= sheet) continue
    sum += sheetList[i].total
    n++
  }
  return n ? sum / n : 0
}

function sheetTotal(sessions, projectId, sheet) {
  var sum = 0
  for (var i = 0; i < sessions.length; i++) {
    var s = sessions[i]
    if (s.project === projectId && s.sheet === sheet) sum += s.end - s.start
  }
  return sum
}

// ---- Headline numbers -------------------------------------------------------

function streaks(dayMap, now, dsh) {
  var keys = Object.keys(dayMap).filter(function(k) { return dayMap[k].total > 0 }).sort()
  var longest = 0
  var run = 0
  var prev = null
  for (var i = 0; i < keys.length; i++) {
    var day = dayMap[keys[i]].start
    run = prev !== null && dayKey(addDays(prev, 1, dsh)) === keys[i] ? run + 1 : 1
    longest = Math.max(longest, run)
    prev = day
  }
  // The current streak survives a day that has not had its session yet.
  var today = dayStartOf(now, dsh)
  var cursor = dayMap[dayKey(today)] && dayMap[dayKey(today)].total > 0 ? today : addDays(today, -1, dsh)
  var current = 0
  while (dayMap[dayKey(cursor)] && dayMap[dayKey(cursor)].total > 0) {
    current++
    cursor = addDays(cursor, -1, dsh)
  }
  return { current: current, longest: longest }
}

function median(values) {
  if (!values.length) return 0
  var sorted = values.slice().sort(function(a, b) { return a - b })
  var mid = Math.floor(sorted.length / 2)
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
}

// Minutes after the logical day start, so 01:30 sorts after 23:00.
function minutesIntoDay(ms, dsh) {
  return Math.floor((ms - dayStartOf(ms, dsh)) / Store.MINUTE)
}

function facts(sessions, dsh) {
  var out = {
    total: total(sessions),
    count: sessions.length,
    average: 0,
    median: 0,
    longest: null,
    longestDay: null,
    activeDays: 0,
    perActiveDay: 0,
    earliest: null,
    latest: null,
    nightShare: 0,
    weekendShare: 0,
    busiestWeekday: -1,
    busiestHour: -1
  }
  if (!sessions.length) return out

  var lengths = []
  for (var i = 0; i < sessions.length; i++) {
    var s = sessions[i]
    var len = s.end - s.start
    lengths.push(len)
    if (!out.longest || len > out.longest.end - out.longest.start) out.longest = s
    var startMin = minutesIntoDay(s.start, dsh)
    var endMin = minutesIntoDay(s.end - 1, dsh) + 1
    if (!out.earliest || startMin < out.earliest.minutes) out.earliest = { minutes: startMin, at: s.start }
    if (!out.latest || endMin > out.latest.minutes) out.latest = { minutes: endMin, at: s.end }
  }
  out.average = out.total / sessions.length
  out.median = median(lengths)

  var days = perDay(sessions, dsh)
  for (var key in days) {
    out.activeDays++
    if (!out.longestDay || days[key].total > out.longestDay.total) out.longestDay = { key: key, start: days[key].start, total: days[key].total }
  }
  out.perActiveDay = out.total / out.activeDays

  var grid = punchcard(sessions)
  var night = 0
  var weekend = 0
  var weekdayTotals = [0, 0, 0, 0, 0, 0, 0]
  var hourTotals = []
  for (var h = 0; h < 24; h++) hourTotals.push(0)
  for (var d = 0; d < 7; d++) {
    for (var hh = 0; hh < 24; hh++) {
      var v = grid[d][hh]
      weekdayTotals[d] += v
      hourTotals[hh] += v
      if (hh >= 22 || hh < 5) night += v
      if (d >= 5) weekend += v
    }
  }
  out.nightShare = night / out.total
  out.weekendShare = weekend / out.total
  out.busiestWeekday = indexOfMax(weekdayTotals)
  out.busiestHour = indexOfMax(hourTotals)
  out.weekdayTotals = weekdayTotals
  out.hourTotals = hourTotals
  return out
}

function indexOfMax(values) {
  var best = 0
  for (var i = 1; i < values.length; i++) if (values[i] > values[best]) best = i
  return values[best] > 0 ? best : -1
}

// Largest value in a list of objects, for scaling bars. Never zero, so a
// chart with no data still divides safely.
function maxOf(list, field) {
  var m = 0
  for (var i = 0; i < list.length; i++) m = Math.max(m, field ? list[i][field] : list[i])
  return m > 0 ? m : 1
}

// A "nice" axis maximum in hours: 1, 2, 5, 10, 20, ... so gridlines land on
// round numbers.
function niceHours(ms) {
  var h = ms / HOUR
  var steps = [0.5, 1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20, 25, 30, 40, 50, 60, 80, 100, 150, 200, 300, 500, 1000]
  for (var i = 0; i < steps.length; i++) if (steps[i] >= h) return steps[i] * HOUR
  return Math.ceil(h / 1000) * 1000 * HOUR
}
