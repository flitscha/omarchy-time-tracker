import QtQuick
import qs.Commons
import qs.Ui
import "../Store.js" as Store
import "../Stats.js" as Stats
import "../Glyphs.js" as Glyphs

// Every session, newest first, grouped by day. Click one to fix its times,
// sheet or project; "Add" is for the session you forgot to start.
Column {
  id: root

  property var service: null
  property var look: null

  property string editingId: ""      // session id, "new", or ""
  property int daysShown: 14
  property bool inlineFocused: false
  readonly property bool editing: addForm.fieldFocused || inlineFocused

  readonly property var doc: service ? service.doc : Store.emptyDocument()
  readonly property int dsh: doc.settings.dayStartHour

  // [{ key, start, total, sessions: [newest first] }], newest day first,
  // limited to the days that have sessions within `daysShown`.
  readonly property var days: {
    var cutoff = Stats.addDays(Stats.dayStartOf(Date.now(), dsh), -(daysShown - 1), dsh)
    var groups = []
    var byKey = {}
    for (var i = doc.sessions.length - 1; i >= 0; i--) {
      var s = doc.sessions[i]
      if (s.end < cutoff) break
      var day = Stats.dayStartOf(s.start, dsh)
      var key = Stats.dayKey(day)
      var g = byKey[key]
      if (!g) {
        g = byKey[key] = { key: key, start: day, total: 0, sessions: [] }
        groups.push(g)
      }
      g.total += s.end - s.start
      g.sessions.push(s)
    }
    return groups
  }
  readonly property bool hasOlder: {
    var cutoff = Stats.addDays(Stats.dayStartOf(Date.now(), dsh), -(daysShown - 1), dsh)
    return doc.sessions.length > 0 && doc.sessions[0].end < cutoff
  }

  spacing: Style.space(8)

  function beginEdit(id) {
    inlineFocused = false
    editingId = id
    if (id === "new") addForm.load(null)
  }

  function dayTitle(start) {
    var today = Stats.dayStartOf(Date.now(), dsh)
    if (start === today) return "Today"
    if (start === Stats.addDays(today, -1, dsh)) return "Yesterday"
    return Qt.formatDate(new Date(start), "dddd, d MMMM")
  }

  Item {
    width: parent.width
    height: addButton.implicitHeight

    Label {
      look: root.look
      secondary: true
      anchors.verticalCenter: parent.verticalCenter
      text: root.doc.sessions.length + " sessions in total"
    }

    Button {
      id: addButton
      anchors.right: parent.right
      visible: root.editingId !== "new"
      iconText: Glyphs.plus
      text: "Add a session"
      bordered: true
      foreground: root.look.fg
      fontFamily: root.look.font
      onClicked: root.beginEdit("new")
    }
  }

  SessionEditor {
    id: addForm
    width: parent.width
    look: root.look
    service: root.service
    visible: root.editingId === "new"
    onDone: root.editingId = ""
  }

  Label {
    visible: root.days.length === 0
    look: root.look
    secondary: true
    width: parent.width
    horizontalAlignment: Text.AlignHCenter
    topPadding: Style.space(16)
    bottomPadding: Style.space(16)
    text: root.doc.sessions.length ? "Nothing in the last " + root.daysShown + " days." : "No sessions yet. Start one on the track tab."
  }

  Repeater {
    model: root.days

    Column {
      id: dayBlock
      required property var modelData
      width: root.width
      spacing: Style.space(1)

      Item {
        width: parent.width
        height: dayLabel.implicitHeight + Style.space(6)

        SectionTitle {
          id: dayLabel
          look: root.look
          anchors.bottom: parent.bottom
          text: root.dayTitle(dayBlock.modelData.start)
          detail: Store.duration(dayBlock.modelData.total)
        }
      }

      Repeater {
        model: dayBlock.modelData.sessions

        Column {
          id: entry
          required property var modelData
          width: dayBlock.width

          readonly property var session: modelData
          readonly property var project: Store.projectById(root.doc, session.project)
          readonly property bool open: root.editingId === session.id

          BorderSurface {
            width: parent.width
            height: Style.space(30)
            radius: Style.cornerRadius
            color: rowMouse.containsMouse || entry.open ? Style.hoverFillFor(root.look.fg, root.look.accent) : "transparent"

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.beginEdit(entry.open ? "" : entry.session.id)
            }

            Row {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(10)

              Label {
                look: root.look
                width: Style.space(96)
                text: Store.timeOfDay(entry.session.start) + "–" + Store.timeOfDay(entry.session.end)
                font.features: { "tnum": 1 }
              }

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(8)
                height: width
                radius: width / 2
                color: root.look.projectColor(entry.project)
              }

              Label {
                look: root.look
                width: Style.space(230)
                text: (entry.project ? entry.project.name : "?")
                  + (entry.session.sheet !== null ? "  ·  Sheet " + entry.session.sheet : "")
              }
            }

            Row {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(10)

              Label {
                look: root.look
                secondary: true
                anchors.verticalCenter: parent.verticalCenter
                visible: entry.session.stop !== "manual" && entry.session.stop !== "switch"
                text: Store.STOP_REASONS[entry.session.stop]
              }

              Label {
                look: root.look
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(64)
                horizontalAlignment: Text.AlignRight
                text: Store.duration(entry.session.end - entry.session.start)
              }
            }
          }

          Loader {
            width: parent.width
            active: entry.open
            sourceComponent: SessionEditor {
              look: root.look
              service: root.service
              Component.onCompleted: load(entry.session)
              onDone: root.beginEdit("")
              onFieldFocusedChanged: root.inlineFocused = fieldFocused
            }
          }
        }
      }
    }
  }

  Button {
    visible: root.hasOlder
    anchors.horizontalCenter: parent.horizontalCenter
    text: "Show older"
    iconText: Glyphs.history
    foreground: root.look.fg
    fontFamily: root.look.font
    onClicked: root.daysShown += 28
  }
}
