// The daily backup script in Service.qml, run by bash against throwaway
// folders: it must keep the newest 30 backups, and never delete or write
// anything outside backups/ - not through a symlinked backups/, not through
// a symlinked backup file.
const { test } = require("node:test")
const assert = require("node:assert")
const fs = require("fs")
const os = require("os")
const path = require("path")
const { execFileSync } = require("child_process")

// The script is a JavaScript string expression in the QML; evaluate it as-is.
const qml = fs.readFileSync(path.join(__dirname, "..", "Service.qml"), "utf8")
const expr = /readonly property string backupScript:\s*([\s\S]*?)\n\n/.exec(qml)[1]
const script = new Function("return " + expr)()

function run(dataDir, day) {
  execFileSync("bash", ["-c", script, "backup", dataDir, day])
}

function tmp() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "tt-backup-"))
}

function day(n) {
  return "2026-01-" + String(n).padStart(2, "0")
}

test("copies today's data and keeps the newest 30", () => {
  const dir = tmp()
  fs.mkdirSync(path.join(dir, "backups"))
  fs.writeFileSync(path.join(dir, "data.json"), "today")
  for (let i = 1; i <= 31; i++) fs.writeFileSync(path.join(dir, "backups", "data-" + day(i) + ".json"), "old")
  fs.writeFileSync(path.join(dir, "backups", "notes.txt"), "not a backup")
  run(dir, "2026-02-01")
  const left = fs.readdirSync(path.join(dir, "backups")).sort()
  assert.strictEqual(left.filter(f => f.startsWith("data-")).length, 30)
  assert.ok(left.includes("data-2026-02-01.json"))
  assert.ok(!left.includes("data-2026-01-01.json") && !left.includes("data-2026-01-02.json"))
  assert.ok(left.includes("notes.txt"))
  assert.strictEqual(fs.readFileSync(path.join(dir, "backups", "data-2026-02-01.json"), "utf8"), "today")
})

test("does nothing when backups/ is a symlink", () => {
  const dir = tmp()
  const elsewhere = tmp()
  for (let i = 1; i <= 40; i++) fs.writeFileSync(path.join(elsewhere, "data-" + day(i % 28 + 1) + "-" + i + ".json"), "x")
  const before = fs.readdirSync(elsewhere).length
  fs.symlinkSync(elsewhere, path.join(dir, "backups"))
  fs.writeFileSync(path.join(dir, "data.json"), "today")
  run(dir, "2026-02-01")
  assert.strictEqual(fs.readdirSync(elsewhere).length, before)
  assert.ok(!fs.existsSync(path.join(elsewhere, "data-2026-02-01.json")))
})

test("never deletes or writes through a symlinked backup file", () => {
  const dir = tmp()
  const elsewhere = tmp()
  const victim = path.join(elsewhere, "precious.json")
  fs.writeFileSync(victim, "keep me")
  fs.mkdirSync(path.join(dir, "backups"))
  fs.writeFileSync(path.join(dir, "data.json"), "today")
  // A link among the oldest (the ones cleanup removes) and one under today's name.
  fs.symlinkSync(victim, path.join(dir, "backups", "data-2025-01-01.json"))
  fs.symlinkSync(victim, path.join(dir, "backups", "data-2026-02-01.json"))
  for (let i = 1; i <= 31; i++) fs.writeFileSync(path.join(dir, "backups", "data-" + day(i) + ".json"), "old")
  run(dir, "2026-02-01")
  assert.strictEqual(fs.readFileSync(victim, "utf8"), "keep me")
  assert.ok(fs.lstatSync(path.join(dir, "backups", "data-2025-01-01.json")).isSymbolicLink())
})

test("skips an empty data.json", () => {
  const dir = tmp()
  fs.mkdirSync(path.join(dir, "backups"))
  fs.writeFileSync(path.join(dir, "data.json"), "")
  run(dir, "2026-02-01")
  assert.deepStrictEqual(fs.readdirSync(path.join(dir, "backups")), [])
})
