.pragma library

// Pure data layer: parsing, serialising and copy-on-write edits of the
// time-tracker document. Nothing in here touches QML or the filesystem, so the
// whole file runs under node for the tests in tests/.
//
// Every edit returns a fresh document instead of mutating the old one. QML
// only re-evaluates bindings when a property is reassigned, so handing the
// service a new object is what makes the popup redraw.

var VERSION = 1
var SECOND = 1000
var MINUTE = 60 * SECOND
var HOUR = 60 * MINUTE
var DAY = 24 * HOUR

// Sessions shorter than this are treated as misclicks and never stored.
var MIN_SESSION = MINUTE

var MODES = ["counter", "sheets"]
var COLOR_SLOTS = 8

var STOP_REASONS = {
  manual: "Stopped",
  "switch": "Switched",
  sheet: "Sheet done",
  lock: "Screen locked",
  suspend: "Suspended",
  shutdown: "Shutdown",
  crash: "Shell gone",
  added: "Added by hand"
}

function emptyDocument() {
  return { version: VERSION, settings: { dayStartHour: 4 }, projects: [], sessions: [] }
}

function isFiniteNumber(value) {
  return typeof value === "number" && isFinite(value)
}

function clampInt(value, min, max, fallback) {
  var n = Math.round(Number(value))
  if (!isFinite(n)) return fallback
  return Math.max(min, Math.min(max, n))
}

function newId(prefix) {
  return prefix + Date.now().toString(36) + Math.floor(Math.random() * 46656).toString(36)
}

function normalizeProject(raw, index) {
  if (!raw || typeof raw !== "object") return null
  var name = String(raw.name || "").trim()
  if (!name || !raw.id) return null
  return {
    id: String(raw.id),
    name: name,
    short: String(raw.short || "").trim(),
    mode: MODES.indexOf(raw.mode) !== -1 ? raw.mode : "counter",
    sheet: clampInt(raw.sheet, 0, 999, 1),
    color: clampInt(raw.color, 0, COLOR_SLOTS - 1, index % COLOR_SLOTS),
    visible: raw.visible !== false,
    created: isFiniteNumber(raw.created) ? raw.created : 0
  }
}

function normalizeSession(raw) {
  if (!raw || typeof raw !== "object") return null
  if (!raw.id || !raw.project) return null
  if (!isFiniteNumber(raw.start) || !isFiniteNumber(raw.end) || raw.end <= raw.start) return null
  return {
    id: String(raw.id),
    project: String(raw.project),
    sheet: isFiniteNumber(raw.sheet) ? Math.round(raw.sheet) : null,
    start: raw.start,
    end: raw.end,
    stop: STOP_REASONS[raw.stop] ? raw.stop : "manual"
  }
}

function normalize(raw) {
  var doc = emptyDocument()
  if (!raw || typeof raw !== "object") return doc
  if (raw.settings && typeof raw.settings === "object")
    doc.settings.dayStartHour = clampInt(raw.settings.dayStartHour, 0, 12, 4)

  var seen = {}
  var projects = Array.isArray(raw.projects) ? raw.projects : []
  for (var i = 0; i < projects.length; i++) {
    var p = normalizeProject(projects[i], i)
    if (p && !seen[p.id]) {
      seen[p.id] = true
      doc.projects.push(p)
    }
  }

  var sessions = Array.isArray(raw.sessions) ? raw.sessions : []
  for (var j = 0; j < sessions.length; j++) {
    var s = normalizeSession(sessions[j])
    if (s) doc.sessions.push(s)
  }
  doc.sessions.sort(function(a, b) { return a.start - b.start })
  return doc
}

// Returns { doc, error }. An empty or missing file is a fresh start, not an
// error; unparseable JSON is, because the caller must not overwrite it.
function parse(text) {
  var trimmed = String(text || "").trim()
  if (!trimmed) return { doc: emptyDocument(), error: "" }
  try {
    return { doc: normalize(JSON.parse(trimmed)), error: "" }
  } catch (e) {
    return { doc: emptyDocument(), error: String(e) }
  }
}

// One project and one session per line, so the file stays readable and a
// git-style diff of two backups shows exactly which sessions changed.
function serialize(doc) {
  function list(items) {
    if (!items.length) return "[]"
    return "[\n" + items.map(function(item) { return "    " + JSON.stringify(item) }).join(",\n") + "\n  ]"
  }
  return "{\n"
    + "  \"version\": " + VERSION + ",\n"
    + "  \"settings\": " + JSON.stringify(doc.settings) + ",\n"
    + "  \"projects\": " + list(doc.projects) + ",\n"
    + "  \"sessions\": " + list(doc.sessions) + "\n"
    + "}\n"
}

function copy(doc) {
  return {
    version: VERSION,
    settings: Object.assign({}, doc.settings),
    projects: doc.projects.slice(),
    sessions: doc.sessions.slice()
  }
}

// ---- Projects -------------------------------------------------------------

function projectById(doc, id) {
  for (var i = 0; i < doc.projects.length; i++)
    if (doc.projects[i].id === id) return doc.projects[i]
  return null
}

function projectIndex(doc, id) {
  for (var i = 0; i < doc.projects.length; i++)
    if (doc.projects[i].id === id) return i
  return -1
}

// The least-used slot, lowest first: new projects walk the palette in its
// validated order and only reuse a hue once all eight are taken.
function nextColor(doc) {
  var counts = []
  for (var c = 0; c < COLOR_SLOTS; c++) counts.push(0)
  for (var i = 0; i < doc.projects.length; i++) counts[doc.projects[i].color]++
  var best = 0
  for (var k = 1; k < COLOR_SLOTS; k++) if (counts[k] < counts[best]) best = k
  return best
}

// Short label for the bar: the explicit short name, or the first word cut to
// six characters ("Optimierung" -> "Optimi", "Linux ricing" -> "Linux").
function shortName(project) {
  if (!project) return ""
  if (project.short) return project.short
  var first = project.name.split(/\s+/)[0]
  return first.length > 6 ? first.slice(0, 6) : first
}

function sheetLabel(project, sheet) {
  if (!project || project.mode !== "sheets") return ""
  var n = sheet === undefined || sheet === null ? project.sheet : sheet
  return "Sheet " + n
}

function addProject(doc, fields) {
  var next = copy(doc)
  var project = normalizeProject({
    id: newId("p"),
    name: fields.name,
    short: fields.short,
    mode: fields.mode,
    sheet: fields.sheet === undefined ? 1 : fields.sheet,
    color: fields.color === undefined ? nextColor(doc) : fields.color,
    visible: true,
    created: Date.now()
  }, doc.projects.length)
  if (!project) return { doc: doc, project: null }
  next.projects.push(project)
  return { doc: next, project: project }
}

function updateProject(doc, id, patch) {
  var index = projectIndex(doc, id)
  if (index === -1) return doc
  var merged = Object.assign({}, doc.projects[index], patch, { id: id })
  var project = normalizeProject(merged, index)
  if (!project) return doc
  var next = copy(doc)
  next.projects[index] = project
  return next
}

function moveProject(doc, id, delta) {
  var index = projectIndex(doc, id)
  var target = index + delta
  if (index === -1 || target < 0 || target >= doc.projects.length) return doc
  var next = copy(doc)
  var moved = next.projects.splice(index, 1)[0]
  next.projects.splice(target, 0, moved)
  return next
}

// Deleting a project takes its sessions with it; hiding is the non-lossy way
// to get an old course out of the list.
function deleteProject(doc, id) {
  if (projectIndex(doc, id) === -1) return doc
  var next = copy(doc)
  next.projects = next.projects.filter(function(p) { return p.id !== id })
  next.sessions = next.sessions.filter(function(s) { return s.project !== id })
  return next
}

// ---- Sessions ---------------------------------------------------------------

function sessionIndex(doc, id) {
  for (var i = 0; i < doc.sessions.length; i++)
    if (doc.sessions[i].id === id) return i
  return -1
}

function insertSorted(list, session) {
  var i = list.length
  while (i > 0 && list[i - 1].start > session.start) i--
  list.splice(i, 0, session)
}

function addSession(doc, fields) {
  var session = normalizeSession({
    id: newId("s"),
    project: fields.project,
    sheet: fields.sheet,
    start: fields.start,
    end: fields.end,
    stop: fields.stop
  })
  if (!session || !projectById(doc, session.project)) return { doc: doc, session: null }
  var next = copy(doc)
  insertSorted(next.sessions, session)
  return { doc: next, session: session }
}

function updateSession(doc, id, patch) {
  var index = sessionIndex(doc, id)
  if (index === -1) return doc
  var session = normalizeSession(Object.assign({}, doc.sessions[index], patch, { id: id }))
  if (!session || !projectById(doc, session.project)) return doc
  var next = copy(doc)
  next.sessions.splice(index, 1)
  insertSorted(next.sessions, session)
  return next
}

function deleteSession(doc, id) {
  var index = sessionIndex(doc, id)
  if (index === -1) return doc
  var next = copy(doc)
  next.sessions.splice(index, 1)
  return next
}

// ---- Active session ---------------------------------------------------------
//
// The running session lives in its own small file (active.json) that the
// service rewrites as a heartbeat. `seen` is the last moment the shell was
// known to be alive, `boot` the kernel boot id at that moment.

function parseActive(text) {
  try {
    var raw = JSON.parse(String(text || "").trim() || "null")
    if (!raw || typeof raw !== "object" || !raw.project || !isFiniteNumber(raw.start)) return null
    return {
      project: String(raw.project),
      sheet: isFiniteNumber(raw.sheet) ? Math.round(raw.sheet) : null,
      start: raw.start,
      seen: isFiniteNumber(raw.seen) ? raw.seen : raw.start,
      boot: String(raw.boot || "")
    }
  } catch (e) {
    return null
  }
}

// What to do with an active session found on startup:
//   "resume" - same boot and the heartbeat is fresh: the shell was only
//              restarted, keep the clock running.
//   "close"  - reboot, or the shell was gone for a while: end the session at
//              the last heartbeat. `reason` says which, for the log.
function recoverActive(active, bootId, now, graceMs) {
  if (!active) return { action: "none" }
  if (active.boot && bootId && active.boot !== bootId)
    return { action: "close", end: active.seen, reason: "shutdown" }
  if (now - active.seen <= graceMs) return { action: "resume" }
  return { action: "close", end: active.seen, reason: "crash" }
}

// Turns an active session into a stored one. Returns the unchanged document
// when the session is too short to be real.
function closeActive(doc, active, end, reason) {
  if (!active || end - active.start < MIN_SESSION) return { doc: doc, session: null }
  return addSession(doc, {
    project: active.project,
    sheet: active.sheet,
    start: active.start,
    end: end,
    stop: reason
  })
}

// ---- Formatting -------------------------------------------------------------

function pad2(n) {
  return (n < 10 ? "0" : "") + n
}

// "0:42" / "3:05" -- compact, for the bar.
function clockDuration(ms) {
  var minutes = Math.floor(Math.max(0, ms) / MINUTE)
  return Math.floor(minutes / 60) + ":" + pad2(minutes % 60)
}

// "42m" / "3h 05m" / "112h" -- for lists and stats.
function duration(ms) {
  var minutes = Math.round(Math.max(0, ms) / MINUTE)
  if (minutes < 60) return minutes + "m"
  var h = Math.floor(minutes / 60)
  if (h >= 100) return h + "h"
  return h + "h " + pad2(minutes % 60) + "m"
}

// "1:02:07" -- the running session in the popup.
function stopwatch(ms) {
  var seconds = Math.floor(Math.max(0, ms) / SECOND)
  var h = Math.floor(seconds / 3600)
  return h + ":" + pad2(Math.floor(seconds / 60) % 60) + ":" + pad2(seconds % 60)
}

function hours(ms) {
  var h = ms / HOUR
  return h >= 10 ? String(Math.round(h)) : (Math.round(h * 10) / 10).toString()
}

function timeOfDay(ms) {
  var d = new Date(ms)
  return pad2(d.getHours()) + ":" + pad2(d.getMinutes())
}

// "2026-09-24 14:05" <-> ms, for the log editor.
function formatDateTime(ms) {
  var d = new Date(ms)
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate()) + " " + timeOfDay(ms)
}

function parseDateTime(text) {
  var m = /^\s*(\d{4})-(\d{1,2})-(\d{1,2})[ T]+(\d{1,2}):(\d{2})\s*$/.exec(String(text || ""))
  if (!m) return NaN
  var d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]))
  if (d.getMonth() !== Number(m[2]) - 1 || Number(m[4]) > 23) return NaN
  return d.getTime()
}
