import QtQuick
import qs.Commons
import qs.Ui
import "../Store.js" as Store
import "../Stats.js" as Stats
import "../Glyphs.js" as Glyphs

// The everyday tab: what is running, and one row per visible project to
// start or stop it with a single click. Sheet projects get ‹ › beside the
// sheet number; › means "this sheet is done".
Column {
  id: root

  property var service: null
  property var look: null
  readonly property bool editing: false

  signal navigate(string target)

  readonly property var doc: service ? service.doc : Store.emptyDocument()
  readonly property var active: service ? service.active : null
  readonly property real now: service ? service.now : Date.now()
  readonly property int dsh: doc.settings.dayStartHour
  readonly property var visibleProjects: doc.projects.filter(function(p) { return p.visible })

  // Finished sessions plus the running one, for every total on this tab.
  readonly property var sessions: Stats.withActive(doc.sessions, active, now)
  readonly property real todayStart: Stats.dayStartOf(now, dsh)
  readonly property real weekStart: Stats.weekStartOf(now, dsh)

  spacing: Style.space(10)

  function sheetTotal(project, sheet) {
    return Stats.sheetTotal(sessions, project.id, sheet)
  }

  function projectTotal(project, from) {
    var sum = 0
    for (var i = 0; i < sessions.length; i++) {
      var s = sessions[i]
      if (s.project === project.id && s.end > from) sum += s.end - Math.max(s.start, from)
    }
    return sum
  }

  // ---- Running session --------------------------------------------------------

  BorderSurface {
    id: runningCard
    visible: root.active !== null && root.service.activeProject !== null
    width: parent.width
    height: visible ? runningColumn.implicitHeight + Style.space(24) : 0
    radius: Style.cornerRadius
    color: Style.normalFillFor(root.look.fg, root.look.accent)
    borderSpec: Border.controlSpec("selected", root.look.fg, root.look.accent)

    readonly property var project: root.service ? root.service.activeProject : null

    Rectangle {
      x: runningCard.borderLeft
      y: runningCard.borderTop
      width: Style.space(4)
      height: parent.height - runningCard.borderTop - runningCard.borderBottom
      color: root.look.projectColor(runningCard.project)
    }

    Column {
      id: runningColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(18)
      anchors.rightMargin: Style.space(12)
      spacing: Style.space(6)

      Item {
        width: parent.width
        height: Math.max(runningText.implicitHeight, stopButton.implicitHeight)

        Column {
          id: runningText
          anchors.left: parent.left
          anchors.right: clock.left
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Label {
            look: root.look
            width: parent.width
            text: runningCard.project ? runningCard.project.name + (root.active.sheet !== null ? "  ·  Sheet " + root.active.sheet : "") : ""
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Label {
            look: root.look
            secondary: true
            width: parent.width
            text: {
              if (!runningCard.project) return ""
              var parts = ["since " + Store.timeOfDay(root.active.start)]
              if (root.active.sheet !== null)
                parts.push("sheet so far " + Store.duration(root.sheetTotal(runningCard.project, root.active.sheet)))
              parts.push("today " + Store.duration(root.projectTotal(runningCard.project, root.todayStart)))
              return parts.join("  ·  ")
            }
          }
        }

        Text {
          id: clock
          anchors.right: stopButton.left
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: Store.stopwatch(root.service ? root.service.elapsed : 0)
          color: root.look.fg
          font.family: root.look.font
          font.pixelSize: Style.font.display
          font.bold: true
        }

        Button {
          id: stopButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          iconText: Glyphs.stop
          text: "Stop"
          bordered: true
          foreground: root.look.fg
          fontFamily: root.look.font
          onClicked: root.service.stop()
        }
      }

      // Forgot to press start? Pull the start time back in 5-minute steps.
      Row {
        spacing: Style.space(4)

        Label {
          look: root.look
          secondary: true
          anchors.verticalCenter: parent.verticalCenter
          text: "Started"
          rightPadding: Style.space(4)
        }

        Button {
          text: "−15m"
          fontSize: Style.font.caption
          verticalPadding: Style.space(2)
          foreground: root.look.fg
          fontFamily: root.look.font
          tooltipText: "I started 15 minutes earlier"
          onClicked: root.service.shiftActiveStart(-15 * Store.MINUTE)
        }

        Button {
          text: "−5m"
          fontSize: Style.font.caption
          verticalPadding: Style.space(2)
          foreground: root.look.fg
          fontFamily: root.look.font
          tooltipText: "I started 5 minutes earlier"
          onClicked: root.service.shiftActiveStart(-5 * Store.MINUTE)
        }

        Button {
          text: "+5m"
          fontSize: Style.font.caption
          verticalPadding: Style.space(2)
          foreground: root.look.fg
          fontFamily: root.look.font
          tooltipText: "I started 5 minutes later"
          onClicked: root.service.shiftActiveStart(5 * Store.MINUTE)
        }
      }
    }
  }

  // ---- Automatic stop ---------------------------------------------------------

  BorderSurface {
    id: resumeCard
    readonly property var interruption: root.service ? root.service.interruption : null
    readonly property var project: interruption ? Store.projectById(root.doc, interruption.project) : null
    visible: root.active === null && project !== null
    width: parent.width
    height: visible ? Math.max(resumeText.implicitHeight, resumeButtons.implicitHeight) + Style.space(20) : 0
    radius: Style.cornerRadius
    color: Style.normalFillFor(root.look.fg, root.look.accent)
    borderSpec: Border.controlSpec("normal", root.look.fg, root.look.accent)

    Column {
      id: resumeText
      anchors.left: parent.left
      anchors.right: resumeButtons.left
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Label {
        look: root.look
        width: parent.width
        text: resumeCard.interruption ? Store.STOP_REASONS[resumeCard.interruption.reason] + " at " + Store.timeOfDay(resumeCard.interruption.at) : ""
        font.bold: true
      }

      Label {
        look: root.look
        secondary: true
        width: parent.width
        text: resumeCard.project
          ? "Stopped " + resumeCard.project.name
            + (resumeCard.interruption.sheet !== null ? " · Sheet " + resumeCard.interruption.sheet : "")
            + " automatically"
          : ""
      }
    }

    Row {
      id: resumeButtons
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      Button {
        iconText: Glyphs.play
        text: "Resume"
        bordered: true
        foreground: root.look.fg
        fontFamily: root.look.font
        onClicked: root.service.resume()
      }

      Button {
        iconText: Glyphs.close
        foreground: root.look.fg
        fontFamily: root.look.font
        tooltipText: "Dismiss"
        onClicked: root.service.dismissInterruption()
      }
    }
  }

  // ---- Projects ---------------------------------------------------------------

  Column {
    width: parent.width
    spacing: Style.space(4)

    Repeater {
      model: root.visibleProjects

      ProjectRow {
        required property var modelData
        width: parent.width
        project: modelData
        view: root
      }
    }
  }

  Column {
    visible: root.visibleProjects.length === 0
    width: parent.width
    spacing: Style.space(8)
    topPadding: Style.space(12)
    bottomPadding: Style.space(12)

    Label {
      look: root.look
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: root.doc.projects.length ? "All projects are hidden." : "No projects yet."
    }

    Button {
      anchors.horizontalCenter: parent.horizontalCenter
      iconText: Glyphs.plus
      text: root.doc.projects.length ? "Show some" : "Create a course or project"
      bordered: true
      foreground: root.look.fg
      fontFamily: root.look.font
      onClicked: root.navigate("projects")
    }
  }

  // ---- Footer -----------------------------------------------------------------

  PanelSeparator {
    width: parent.width
    foreground: root.look.fg
  }

  Row {
    width: parent.width
    spacing: Style.space(18)

    readonly property var streak: Stats.streaks(Stats.perDay(root.doc.sessions, root.dsh), root.now, root.dsh)

    Label {
      look: root.look
      secondary: true
      text: "Today " + Store.duration(Stats.total(Stats.clip(root.sessions, root.todayStart, root.now + 1)))
    }

    Label {
      look: root.look
      secondary: true
      text: "This week " + Store.duration(Stats.total(Stats.clip(root.sessions, root.weekStart, root.now + 1)))
    }

    Label {
      look: root.look
      secondary: true
      visible: parent.streak.current > 1
      text: Glyphs.fire + " " + parent.streak.current + " days in a row"
    }
  }
}
