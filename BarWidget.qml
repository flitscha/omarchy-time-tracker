import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Store.js" as Store
import "Glyphs.js" as Glyphs

// The bar pill. Idle it is a single timer icon; while a session runs it
// reads "Opt 3  0:42" (short name, sheet, time in this session).
//
//   left click    popup (track / log / stats / projects)
//   right click   stop the running session, or resume after an automatic stop
//   middle click  restart the most recent project
BarWidget {
  id: root
  moduleName: "felix.punchcard"

  // The service is created by the shell, possibly after this widget, and a
  // function call in a binding would never be re-evaluated. Poll until it
  // shows up.
  property var service: null

  Timer {
    interval: 300
    repeat: true
    triggeredOnStart: true
    running: root.service === null
    onTriggered: {
      if (root.bar && root.bar.shell && typeof root.bar.shell.serviceFor === "function")
        root.service = root.bar.shell.serviceFor(root.moduleName)
    }
  }

  readonly property bool running: !!(service && service.active)
  readonly property var project: service ? service.activeProject : null
  readonly property var interruption: service ? service.interruption : null
  readonly property var interruptedProject: interruption && service ? Store.projectById(service.doc, interruption.project) : null
  readonly property bool showResume: !running && !!interruptedProject && interruption.announced

  readonly property string sheetSuffix: running && service.active.sheet !== null ? " " + service.active.sheet : ""
  readonly property string pillText: {
    if (running && project)
      return Glyphs.timerRunning + " " + Store.shortName(project) + sheetSuffix + "  " + Store.clockDuration(service.elapsed)
    if (showResume)
      return Glyphs.pause + " " + Store.shortName(interruptedProject)
    return Glyphs.timerIdle
  }

  readonly property string tooltip: {
    if (!service) return "Punchcard"
    if (service.loadError) return "Punchcard: " + service.loadError
    if (running && project) {
      var sheetText = service.active.sheet !== null ? " · Sheet " + service.active.sheet : ""
      return project.name + sheetText + " — since " + Store.timeOfDay(service.active.start)
        + " (" + Store.duration(service.elapsed) + ")\nRight click to stop"
    }
    if (showResume)
      return Store.STOP_REASONS[interruption.reason] + " at " + Store.timeOfDay(interruption.at)
        + " — right click to resume " + interruptedProject.name
    return "Punchcard — nothing running"
  }

  function lastProjectId() {
    if (!service) return ""
    var sessions = service.doc.sessions
    return sessions.length ? sessions[sessions.length - 1].project : ""
  }

  function quickAction(button) {
    if (!service) return
    if (button === Qt.RightButton) {
      if (running) service.stop()
      else if (interruption) service.resume()
    } else if (button === Qt.MiddleButton) {
      if (running) service.stop()
      else if (lastProjectId()) service.start(lastProjectId())
    } else {
      toggle()
    }
  }

  // ---- Popup shape contract (open/close/opened on the widget root) ----------

  property bool popupOpen: false
  property bool popoutSwitchClosing: false
  readonly property bool opened: popupOpen

  function open() { popupOpen = true }
  function close() { popupOpen = false }
  function toggle() { popupOpen = !popupOpen }
  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() { root.popoutSwitchClosing = false })
  }

  // ---- Pill ---------------------------------------------------------------------

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.pillText
    horizontalMargin: 6
    active: root.running
    activeColor: Color.accent
    dimmed: root.showResume && !pulse.running
    tooltipText: root.tooltip
    onPressed: function(b) { root.quickAction(b) }
  }

  // After an automatic stop the icon blinks for a few seconds once the screen
  // is back, then stays dimmed until resumed or dismissed.
  SequentialAnimation {
    id: pulse
    loops: 6
    NumberAnimation { target: button; property: "opacity"; to: 0.25; duration: 450; easing.type: Easing.InOutSine }
    NumberAnimation { target: button; property: "opacity"; to: 1.0; duration: 450; easing.type: Easing.InOutSine }
  }

  Connections {
    target: root.service
    function onInterruptionAnnounced() { pulse.restart() }
  }

  Popup {
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.popupOpen
    service: root.service
    onCloseRequested: root.close()
  }
}
