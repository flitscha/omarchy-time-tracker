import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "Store.js" as Store
import "Demo.js" as Demo

// The clock itself. Headless and keepLoaded, so the running session survives
// bar reloads and popup rebuilds; the bar widget only reads this object and
// calls its methods.
//
// Files, in $XDG_DATA_HOME/punchcard (default ~/.local/share/punchcard):
//   data.json    projects and finished sessions, rewritten on every change
//   active.json  the running session plus a heartbeat, rewritten every 20 s
//   backups/     one copy of data.json per day, the last 30 kept
//
// Safety nets, all driven by the heartbeat rather than by shutdown hooks
// (a shell killed at shutdown never gets to run one):
//   - shutdown / crash: on startup an active session whose heartbeat is from
//     another boot, or older than 90 s, is closed at its last heartbeat.
//     A younger one is a shell restart and simply keeps running.
//   - suspend: the one-second tick notices a jump in wall-clock time and
//     closes the session where the ticks stopped.
//   - screen lock: Hyprland is polled every 5 s while a session runs; a lock
//     closes it at the moment it was seen.
// Each automatic stop leaves an `interruption` behind, which the bar shows as
// a pulsing icon once the screen is unlocked again; one tap resumes.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string dataDir: {
    var base = Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")
    return base + "/punchcard"
  }

  property var doc: Store.emptyDocument()
  property var active: null
  property var interruption: null
  property real now: Date.now()

  property bool ready: false
  property string loadError: ""
  property bool demo: false
  property int revision: 0

  readonly property var activeProject: active ? Store.projectById(doc, active.project) : null
  readonly property real elapsed: active ? Math.max(0, now - active.start) : 0
  readonly property int dayStartHour: doc.settings.dayStartHour

  // Raised once the screen is usable again after an automatic stop, so the
  // bar pulses where it can be seen rather than behind the lock screen.
  signal interruptionAnnounced()

  // ---- Loading --------------------------------------------------------------

  property string bootId: ""
  property bool dataLoaded: false
  property bool activeLoaded: false
  property bool bootLoaded: false

  Process {
    id: mkdirProc
    running: true
    command: ["mkdir", "-p", root.dataDir + "/backups"]
    onExited: {
      dataFile.path = root.dataDir + "/data.json"
      activeFile.path = root.dataDir + "/active.json"
    }
  }

  FileView {
    id: bootFile
    path: "/proc/sys/kernel/random/boot_id"
    printErrors: false
    onLoaded: { root.bootId = text().trim(); root.bootLoaded = true; root.finishLoading() }
    onLoadFailed: { root.bootLoaded = true; root.finishLoading() }
  }

  FileView {
    id: dataFile
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var parsed = Store.parse(text())
      if (parsed.error) {
        // Never overwrite a file we could not read; the popup shows the error
        // and the user can repair or move the file.
        root.loadError = "data.json is not valid JSON: " + parsed.error
        console.warn("punchcard: " + root.loadError)
      } else {
        root.doc = parsed.doc
      }
      root.dataLoaded = true
      root.finishLoading()
    }
    onLoadFailed: function(error) {
      if (error !== FileViewError.FileNotFound) {
        root.loadError = "could not read data.json (error " + error + ")"
        console.warn("punchcard: " + root.loadError)
      }
      root.dataLoaded = true
      root.finishLoading()
    }
    onSaveFailed: function(error) { console.warn("punchcard: saving data.json failed, error " + error) }
  }

  FileView {
    id: activeFile
    atomicWrites: true
    printErrors: false
    onLoaded: { root.pendingActive = Store.parseActive(text()); root.activeLoaded = true; root.finishLoading() }
    onLoadFailed: { root.activeLoaded = true; root.finishLoading() }
    onSaveFailed: function(error) { console.warn("punchcard: saving active.json failed, error " + error) }
  }

  property var pendingActive: null

  function finishLoading() {
    if (ready || !dataLoaded || !activeLoaded || !bootLoaded) return
    var t = Date.now()
    var recovery = Store.recoverActive(pendingActive, bootId, t, 90 * Store.SECOND)
    if (recovery.action === "resume") {
      active = pendingActive
    } else if (recovery.action === "close") {
      var closed = Store.closeActive(doc, pendingActive, recovery.end, recovery.reason)
      if (closed.session) commit(closed.doc)
      interrupt(pendingActive, recovery.end, recovery.reason)
      writeActive()
    }
    pendingActive = null
    now = t
    lastTick = t
    ready = true
  }

  // ---- Persistence ------------------------------------------------------------

  property string lastBackupDay: ""

  function commit(next) {
    doc = next
    revision++
    save()
  }

  function save() {
    if (demo || loadError || !dataLoaded) return
    // The day's first write waits for the backup copy, so the copy holds the
    // state from before the change; backupProc writes when it is done.
    if (backupDue()) startBackup()
    else if (!backupProc.running) dataFile.setText(Store.serialize(doc))
  }

  function writeActive() {
    if (demo || !activeFile.path) return
    if (active) {
      active = Object.assign({}, active, { seen: Date.now(), boot: bootId })
      activeFile.setText(JSON.stringify(active) + "\n")
    } else {
      activeFile.setText("")
    }
  }

  function today() {
    return Store.formatDateTime(Date.now()).slice(0, 10)
  }

  function backupDue() {
    return today() !== lastBackupDay
  }

  // One copy per day, the newest 30 kept.
  function startBackup() {
    lastBackupDay = today()
    backupProc.command = ["bash", "-c",
      "[ -s \"$1/data.json\" ] || exit 0; "
      + "cp -n \"$1/data.json\" \"$1/backups/data-$2.json\"; "
      + "ls -1 \"$1/backups\"/data-*.json | head -n -30 | xargs -r rm --",
      "backup", dataDir, lastBackupDay]
    backupProc.running = true
  }

  Process {
    id: backupProc
    onExited: if (!root.demo && !root.loadError) dataFile.setText(Store.serialize(root.doc))
  }


  // ---- The clock --------------------------------------------------------------

  property real lastTick: Date.now()
  property int tickCount: 0

  Timer {
    id: ticker
    interval: 1000
    repeat: true
    running: root.ready
    onTriggered: root.tick()
  }

  function tick() {
    var t = Date.now()
    var gap = t - lastTick
    now = t
    tickCount++
    if (active && gap > 30 * Store.SECOND) {
      // The timer froze for longer than any busy shell would: the machine
      // was asleep. The session ends where the ticks stopped.
      autoStop(lastTick, "suspend")
    } else if (active) {
      if (tickCount % 20 === 0) writeActive()
      if (tickCount % 5 === 0) pollLock()
    } else if (interruption && !interruption.announced) {
      if (tickCount % 2 === 0) pollLock()
    } else if (interruption && t - interruption.at > 3 * Store.HOUR) {
      interruption = null
    }
    lastTick = t
  }

  // Hyprland has no lock event, but an active ext-session-lock shows up as
  // LOCK in every monitor's solitaryBlockedBy (the same probe
  // omarchy-hyprland-session-locked uses). The value read here is from the
  // previous refresh, which is at most one poll old.
  function screenLocked() {
    var monitors = Hyprland.monitors.values
    for (var i = 0; i < monitors.length; i++) {
      var ipc = monitors[i].lastIpcObject
      var blockers = ipc && ipc.solitaryBlockedBy ? ipc.solitaryBlockedBy : []
      if (blockers.indexOf("LOCK") !== -1) return true
    }
    return false
  }

  // Counts consecutive unlocked readings. The first reading after a resume
  // can still be the one taken before the machine slept, so an interruption
  // is only announced once two fresh polls agree the screen is open.
  property int unlockedPolls: 0

  function pollLock() {
    var locked = screenLocked()
    Hyprland.refreshMonitors()
    unlockedPolls = locked ? 0 : unlockedPolls + 1
    if (active && locked) {
      autoStop(Date.now(), "lock")
    } else if (!active && interruption && !interruption.announced && unlockedPolls >= 2) {
      interruption = Object.assign({}, interruption, { announced: true })
      interruptionAnnounced()
    }
  }

  function autoStop(end, reason) {
    var stopped = active
    finishActive(end, reason)
    interrupt(stopped, end, reason)
  }

  function interrupt(stopped, at, reason) {
    if (!stopped || !Store.projectById(doc, stopped.project)) return
    unlockedPolls = 0
    interruption = { project: stopped.project, sheet: stopped.sheet, at: at, reason: reason, announced: false }
  }

  function finishActive(end, reason) {
    if (!active) return
    var closed = Store.closeActive(doc, active, end, reason)
    active = null
    if (closed.session) commit(closed.doc)
    writeActive()
  }

  // ---- Commands (called by the bar widget and over IPC) ------------------------

  function start(projectId) {
    var project = Store.projectById(doc, projectId)
    if (!project || !ready) return false
    var sheet = project.mode === "sheets" ? project.sheet : null
    if (active && active.project === projectId && active.sheet === sheet) return true
    var t = Date.now()
    if (active) finishActive(t, "switch")
    interruption = null
    active = { project: projectId, sheet: sheet, start: t, seen: t, boot: bootId }
    now = t
    writeActive()
    return true
  }

  function stop() {
    if (!active) return false
    finishActive(Date.now(), "manual")
    return true
  }

  function toggle(projectId) {
    if (active && active.project === projectId) return stop()
    return start(projectId)
  }

  // Picks up where an automatic stop left off, on the sheet it was on then.
  function resume() {
    if (!interruption) return false
    var i = interruption
    var project = Store.projectById(doc, i.project)
    if (!project) { interruption = null; return false }
    if (project.mode === "sheets" && i.sheet !== null && project.sheet !== i.sheet)
      commit(Store.updateProject(doc, project.id, { sheet: i.sheet }))
    return start(project.id)
  }

  function dismissInterruption() {
    interruption = null
  }

  // "Next sheet" means this one is done: a running session on it ends there.
  function nextSheet(projectId) {
    var project = Store.projectById(doc, projectId)
    if (!project || project.mode !== "sheets") return false
    if (active && active.project === projectId) finishActive(Date.now(), "sheet")
    commit(Store.updateProject(doc, projectId, { sheet: project.sheet + 1 }))
    return true
  }

  // Going back is for catching up on an old sheet: a running session moves
  // along with it instead of stopping.
  function previousSheet(projectId) {
    var project = Store.projectById(doc, projectId)
    if (!project || project.mode !== "sheets" || project.sheet <= 0) return false
    var wasRunning = active && active.project === projectId
    if (wasRunning) finishActive(Date.now(), "switch")
    commit(Store.updateProject(doc, projectId, { sheet: project.sheet - 1 }))
    if (wasRunning) start(projectId)
    return true
  }

  // Nudges the start of the running session, for "I forgot to press start".
  function shiftActiveStart(deltaMs) {
    if (!active) return
    var t = Date.now()
    var latestSessionEnd = 0
    for (var i = doc.sessions.length - 1; i >= 0 && !latestSessionEnd; i--) latestSessionEnd = doc.sessions[i].end
    var startAt = Math.min(t, Math.max(latestSessionEnd, active.start + deltaMs))
    active = Object.assign({}, active, { start: startAt })
    writeActive()
  }

  function addProject(fields) {
    var r = Store.addProject(doc, fields)
    if (r.project) commit(r.doc)
    return r.project
  }

  function updateProject(id, patch) {
    var before = Store.projectById(doc, id)
    var next = Store.updateProject(doc, id, patch)
    if (next === doc) return false
    // Changing the sheet or mode under a running session splits it, so the
    // time so far stays with the sheet it was spent on.
    var after = Store.projectById(next, id)
    var running = active && active.project === id
    var split = running && (before.mode !== after.mode || before.sheet !== after.sheet)
    if (split) finishActive(Date.now(), "switch")
    commit(next)
    if (split) start(id)
    return true
  }

  function moveProject(id, delta) {
    commit(Store.moveProject(doc, id, delta))
  }

  function deleteProject(id) {
    if (active && active.project === id) {
      active = null
      writeActive()
    }
    if (interruption && interruption.project === id) interruption = null
    commit(Store.deleteProject(doc, id))
  }

  function addSession(fields) {
    var r = Store.addSession(doc, Object.assign({ stop: "added" }, fields))
    if (r.session) commit(r.doc)
    return r.session !== null
  }

  function updateSession(id, patch) {
    var next = Store.updateSession(doc, id, patch)
    if (next === doc) return false
    commit(next)
    return true
  }

  function deleteSession(id) {
    commit(Store.deleteSession(doc, id))
  }

  function setDayStartHour(hour) {
    var next = Store.copy(doc)
    next.settings.dayStartHour = Math.max(0, Math.min(12, Math.round(hour)))
    commit(next)
  }

  // ---- Demo -------------------------------------------------------------------

  function setDemo(on) {
    if (on === demo) return
    if (on) {
      stop()
      demo = true
      active = null
      interruption = null
      doc = Demo.generate(Date.now())
    } else {
      demo = false
      active = null
      ready = false
      dataLoaded = false
      activeLoaded = false
      doc = Store.emptyDocument()
      dataFile.reload()
      activeFile.reload()
    }
    revision++
  }

  // ---- IPC --------------------------------------------------------------------
  //
  //   omarchy-shell punchcard status
  //   omarchy-shell punchcard toggle Optimierung
  //   omarchy-shell punchcard stop | resume | dismiss | next <project> | previous <project>
  //   omarchy-shell punchcard demo on|off

  function findProject(query) {
    var q = String(query || "").trim().toLowerCase()
    if (!q) return null
    var list = doc.projects
    for (var i = 0; i < list.length; i++)
      if (list[i].id === query || list[i].name.toLowerCase() === q || list[i].short.toLowerCase() === q) return list[i]
    for (var j = 0; j < list.length; j++)
      if (list[j].name.toLowerCase().indexOf(q) === 0) return list[j]
    return null
  }

  IpcHandler {
    target: "punchcard"

    function status(): string {
      var p = root.activeProject
      return JSON.stringify({
        running: !!p,
        project: p ? p.name : null,
        sheet: root.active ? root.active.sheet : null,
        elapsedMinutes: Math.floor(root.elapsed / Store.MINUTE),
        interrupted: root.interruption ? root.interruption.reason : null,
        demo: root.demo,
        error: root.loadError || null
      })
    }

    function toggle(project: string): string {
      var p = root.findProject(project)
      if (!p) return "unknown project"
      return root.toggle(p.id) ? "ok" : "failed"
    }

    function start(project: string): string {
      var p = root.findProject(project)
      if (!p) return "unknown project"
      return root.start(p.id) ? "ok" : "failed"
    }

    function stop(): string { return root.stop() ? "ok" : "not running" }
    function resume(): string { return root.resume() ? "ok" : "nothing to resume" }
    function dismiss(): string { root.dismissInterruption(); return "ok" }

    function next(project: string): string {
      var p = root.findProject(project)
      return p && root.nextSheet(p.id) ? "ok" : "failed"
    }

    function previous(project: string): string {
      var p = root.findProject(project)
      return p && root.previousSheet(p.id) ? "ok" : "failed"
    }

    // What the lock detection sees right now, for troubleshooting.
    function probe(): string {
      return JSON.stringify({
        locked: root.screenLocked(),
        blockers: Hyprland.monitors.values.map(function(m) {
          return m.lastIpcObject ? m.lastIpcObject.solitaryBlockedBy || [] : null
        })
      })
    }

    function demo(state: string): string {
      root.setDemo(state === "on" || state === "true" || state === "1")
      return root.demo ? "demo on (nothing is saved)" : "demo off"
    }
  }
}
