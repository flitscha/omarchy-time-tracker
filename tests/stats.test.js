// Run with: TZ=Europe/Vienna node --test tests/
const test = require("node:test")
const assert = require("node:assert/strict")
const Stats = require("./load")("Stats.js")

const H = 3600 * 1000
const M = 60 * 1000
const DSH = 4

function at(y, mo, d, h, mi) {
  return new Date(y, mo - 1, d, h, mi || 0).getTime()
}

function s(project, start, end, sheet) {
  return { id: String(start), project, sheet: sheet === undefined ? null : sheet, start, end, stop: "manual" }
}

test("logical day starts at dayStartHour", () => {
  assert.equal(Stats.dayKey(Stats.dayStartOf(at(2026, 9, 24, 2), DSH)), "2026-09-23")
  assert.equal(Stats.dayKey(Stats.dayStartOf(at(2026, 9, 24, 4), DSH)), "2026-09-24")
  assert.equal(Stats.weekday(Stats.dayStartOf(at(2026, 9, 24, 12), DSH)), 3) // Thursday
})

test("perDay splits a session across the day boundary", () => {
  const days = Stats.perDay([s("a", at(2026, 9, 23, 22), at(2026, 9, 24, 6))], DSH)
  assert.equal(days["2026-09-23"].total, 6 * H)
  assert.equal(days["2026-09-24"].total, 2 * H)
})

test("days are 23h/25h long across DST switches", () => {
  // Europe/Vienna leaves summer time on 2026-10-25.
  const start = Stats.dayStartOf(at(2026, 10, 24, 12), DSH)
  assert.equal(Stats.addDays(start, 1, DSH) - start, 25 * H)
})

test("clip trims to the window", () => {
  const out = Stats.clip([s("a", 0, 10 * H), s("a", 20 * H, 21 * H)], 5 * H, 20.5 * H)
  assert.deepEqual(out.map(x => [x.start, x.end]), [[5 * H, 10 * H], [20 * H, 20.5 * H]])
})

test("punchcard buckets by weekday and clock hour", () => {
  const grid = Stats.punchcard([s("a", at(2026, 9, 21, 9, 30), at(2026, 9, 21, 11))]) // Monday
  assert.equal(grid[0][9], 30 * M)
  assert.equal(grid[0][10], 60 * M)
  assert.equal(grid[1][9], 0)
})

test("timeline lanes carry fractional segments", () => {
  const now = at(2026, 9, 24, 20)
  const lanes = Stats.timeline([s("a", at(2026, 9, 24, 16), at(2026, 9, 24, 22))], 2, now, DSH)
  assert.equal(lanes.length, 2)
  assert.equal(lanes[1].total, 6 * H)
  assert.equal(lanes[1].segments[0].from, 0.5)
  assert.equal(lanes[1].segments[0].to, 0.75)
})

test("sheets aggregates per sheet and averages the earlier ones", () => {
  const list = Stats.sheets([
    s("a", at(2026, 9, 1, 10), at(2026, 9, 1, 12), 1),
    s("a", at(2026, 9, 2, 10), at(2026, 9, 2, 11), 1),
    s("a", at(2026, 9, 8, 10), at(2026, 9, 8, 16), 2),
    s("b", at(2026, 9, 8, 10), at(2026, 9, 8, 16), 1),
    s("a", at(2026, 9, 15, 10), at(2026, 9, 15, 11), 3)
  ], "a", DSH)
  assert.deepEqual(list.map(x => [x.sheet, x.total / H, x.count, x.days]), [[1, 3, 2, 2], [2, 6, 1, 1], [3, 1, 1, 1]])
  assert.equal(Stats.averageBefore(list, 3), 4.5 * H)
  assert.equal(Stats.averageBefore(list, 1), 0)
})

test("streaks count consecutive logical days", () => {
  const now = at(2026, 9, 24, 12)
  const days = Stats.perDay([
    s("a", at(2026, 9, 20, 10), at(2026, 9, 20, 11)),
    s("a", at(2026, 9, 22, 10), at(2026, 9, 22, 11)),
    s("a", at(2026, 9, 24, 1), at(2026, 9, 24, 2)), // still the 23rd
  ], DSH)
  // Nothing yet today: the streak ending yesterday still counts.
  assert.deepEqual(Stats.streaks(days, now, DSH), { current: 2, longest: 2 })
})

test("facts", () => {
  const f = Stats.facts([
    s("a", at(2026, 9, 21, 8), at(2026, 9, 21, 10)),   // Monday morning
    s("a", at(2026, 9, 26, 23), at(2026, 9, 27, 1)),   // Saturday night
  ], DSH)
  assert.equal(f.total, 4 * H)
  assert.equal(f.activeDays, 2)
  assert.equal(f.earliest.minutes, 4 * 60)
  assert.equal(f.latest.minutes, 21 * 60)
  assert.equal(f.nightShare, 0.5)
  assert.equal(f.weekendShare, 0.5)
  assert.equal(Stats.facts([], DSH).count, 0)
})

test("niceHours rounds up to a readable axis", () => {
  assert.equal(Stats.niceHours(0.2 * H), 0.5 * H)
  assert.equal(Stats.niceHours(7 * H), 8 * H)
  assert.equal(Stats.niceHours(41 * H), 50 * H)
})

test("demo semester is sane", () => {
  const Demo = require("./load")("Demo.js")
  const now = at(2026, 9, 24, 12)
  const doc = Demo.generate(now)
  assert.equal(doc.projects.length, 5)
  assert.ok(doc.sessions.length > 100)
  for (let i = 1; i < doc.sessions.length; i++) assert.ok(doc.sessions[i - 1].end <= doc.sessions[i].start)
  assert.ok(doc.sessions.every(x => x.end < now))
})
