// Run with: TZ=Europe/Vienna node --test tests/
const test = require("node:test")
const assert = require("node:assert/strict")
const Store = require("./load")("Store.js")

const H = Store.HOUR
const M = Store.MINUTE

function docWithProject(fields) {
  const r = Store.addProject(Store.emptyDocument(), Object.assign({ name: "Optimierung", mode: "sheets" }, fields))
  return { doc: r.doc, p: r.project }
}

test("parse: empty text is a fresh document, broken JSON is an error", () => {
  assert.deepEqual(Store.parse("").doc.projects, [])
  assert.equal(Store.parse("").error, "")
  const broken = Store.parse("{ nope")
  assert.notEqual(broken.error, "")
})

test("serialize round-trips and puts one session per line", () => {
  let { doc, p } = docWithProject()
  doc = Store.addSession(doc, { project: p.id, sheet: 1, start: 0, end: H, stop: "manual" }).doc
  doc = Store.addSession(doc, { project: p.id, sheet: 1, start: 2 * H, end: 3 * H, stop: "lock" }).doc
  const text = Store.serialize(doc)
  assert.deepEqual(Store.parse(text).doc, doc)
  assert.equal(text.split("\n").filter(l => l.includes("\"stop\"")).length, 2)
})

test("normalize drops invalid sessions and duplicate projects, sorts by start", () => {
  const doc = Store.normalize({
    projects: [{ id: "a", name: "A" }, { id: "a", name: "Dup" }, { id: "b", name: "" }],
    sessions: [
      { id: "1", project: "a", start: 50, end: 60 },
      { id: "2", project: "a", start: 10, end: 20 },
      { id: "3", project: "a", start: 30, end: 30 },
      { id: "4", project: "a", start: "x", end: 40 }
    ]
  })
  assert.deepEqual(doc.projects.map(p => p.name), ["A"])
  assert.deepEqual(doc.sessions.map(s => s.id), ["2", "1"])
  assert.equal(doc.projects[0].mode, "counter")
})

test("edits are copy-on-write", () => {
  const { doc, p } = docWithProject()
  const next = Store.updateProject(doc, p.id, { sheet: 5 })
  assert.equal(doc.projects[0].sheet, 1)
  assert.equal(next.projects[0].sheet, 5)
  assert.notEqual(doc.projects, next.projects)
})

test("new projects walk the palette in order", () => {
  let doc = Store.emptyDocument()
  const colors = []
  for (let i = 0; i < 10; i++) {
    const r = Store.addProject(doc, { name: "P" + i })
    doc = r.doc
    colors.push(r.project.color)
  }
  assert.deepEqual(colors, [0, 1, 2, 3, 4, 5, 6, 7, 0, 1])
})

test("moveProject and deleteProject", () => {
  let doc = Store.emptyDocument()
  const ids = []
  for (const name of ["A", "B", "C"]) {
    const r = Store.addProject(doc, { name })
    doc = r.doc
    ids.push(r.project.id)
  }
  doc = Store.addSession(doc, { project: ids[1], start: 0, end: H }).doc
  doc = Store.moveProject(doc, ids[2], -2)
  assert.deepEqual(doc.projects.map(p => p.name), ["C", "A", "B"])
  assert.equal(Store.moveProject(doc, ids[2], -1), doc)
  doc = Store.deleteProject(doc, ids[1])
  assert.deepEqual(doc.projects.map(p => p.name), ["C", "A"])
  assert.equal(doc.sessions.length, 0)
})

test("sessions: add keeps order, update re-sorts, invalid edits are ignored", () => {
  let { doc, p } = docWithProject()
  doc = Store.addSession(doc, { project: p.id, start: 10 * H, end: 11 * H }).doc
  const first = Store.addSession(doc, { project: p.id, start: 1 * H, end: 2 * H })
  doc = first.doc
  assert.deepEqual(doc.sessions.map(s => s.start), [1 * H, 10 * H])
  doc = Store.updateSession(doc, first.session.id, { start: 20 * H, end: 21 * H })
  assert.deepEqual(doc.sessions.map(s => s.start), [10 * H, 20 * H])
  assert.equal(Store.updateSession(doc, first.session.id, { end: 0 }), doc)
  assert.equal(Store.addSession(doc, { project: "missing", start: 0, end: H }).session, null)
  doc = Store.deleteSession(doc, first.session.id)
  assert.equal(doc.sessions.length, 1)
})

test("closeActive discards misclicks", () => {
  const { doc, p } = docWithProject()
  const active = { project: p.id, sheet: 2, start: 0 }
  assert.equal(Store.closeActive(doc, active, 30 * 1000, "manual").session, null)
  const r = Store.closeActive(doc, active, 5 * M, "lock")
  assert.equal(r.session.sheet, 2)
  assert.equal(r.session.stop, "lock")
})

test("recoverActive tells a shell restart from a shutdown", () => {
  const active = { project: "p", sheet: 1, start: 0, seen: 100 * 1000, boot: "boot-a" }
  assert.equal(Store.recoverActive(active, "boot-a", 130 * 1000, 90 * 1000).action, "resume")
  assert.deepEqual(Store.recoverActive(active, "boot-b", 130 * 1000, 90 * 1000),
    { action: "close", end: 100 * 1000, reason: "shutdown" })
  assert.deepEqual(Store.recoverActive(active, "boot-a", 500 * 1000, 90 * 1000),
    { action: "close", end: 100 * 1000, reason: "crash" })
  assert.equal(Store.recoverActive(null, "boot-a", 0, 0).action, "none")
})

test("parseActive tolerates junk", () => {
  assert.equal(Store.parseActive(""), null)
  assert.equal(Store.parseActive("{}"), null)
  assert.equal(Store.parseActive("{nope"), null)
  assert.equal(Store.parseActive('{"project":"p","start":5}').seen, 5)
})

test("formatting", () => {
  assert.equal(Store.clockDuration(42 * M), "0:42")
  assert.equal(Store.clockDuration(3 * H + 5 * M + 59 * 1000), "3:05")
  assert.equal(Store.duration(42 * M), "42m")
  assert.equal(Store.duration(3 * H + 5 * M), "3h 05m")
  assert.equal(Store.duration(120 * H), "120h")
  assert.equal(Store.stopwatch(H + 2 * M + 7 * 1000), "1:02:07")
  assert.equal(Store.shortName({ name: "Optimierung", short: "" }), "Optimi")
  assert.equal(Store.shortName({ name: "Linux ricing", short: "" }), "Linux")
  assert.equal(Store.shortName({ name: "Optimierung", short: "Opt" }), "Opt")
  assert.equal(Store.sheetLabel({ mode: "sheets", sheet: 3 }), "Sheet 3")
  assert.equal(Store.sheetLabel({ mode: "counter", sheet: 3 }), "")
})

test("date-time parsing round-trips and rejects nonsense", () => {
  const ms = new Date(2026, 8, 24, 14, 5).getTime()
  assert.equal(Store.formatDateTime(ms), "2026-09-24 14:05")
  assert.equal(Store.parseDateTime("2026-09-24 14:05"), ms)
  assert.ok(isNaN(Store.parseDateTime("2026-02-30 10:00")))
  assert.ok(isNaN(Store.parseDateTime("2026-09-24 25:00")))
  assert.ok(isNaN(Store.parseDateTime("yesterday")))
})
