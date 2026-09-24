import QtQuick
import qs.Commons
import qs.Ui
import "../Store.js" as Store
import "../Glyphs.js" as Glyphs

// Edit or add one session. Times are typed as "2026-09-24 14:05"; the
// ±5 minute buttons cover the usual "I stopped too late" fix without typing.
BorderSurface {
  id: root

  property var look: null
  property var service: null
  property var session: null   // null = add

  property string projectId: ""
  property int sheet: 1
  property bool confirmDelete: false
  property string error: ""

  readonly property var project: service ? Store.projectById(service.doc, projectId) : null
  readonly property bool fieldFocused: startField.activeFocus || endField.activeFocus
  readonly property var projects: service ? service.doc.projects.filter(function(p) { return p.visible || p.id === root.projectId }) : []

  signal done()

  onDone: { startField.focus = false; endField.focus = false }

  function load(s) {
    session = s
    confirmDelete = false
    error = ""
    var now = Date.now()
    var fallback = service.doc.projects.filter(function(p) { return p.visible })[0]
    projectId = s ? s.project : (fallback ? fallback.id : "")
    sheet = s && s.sheet !== null ? s.sheet : (project ? project.sheet : 1)
    startField.text = Store.formatDateTime(s ? s.start : now - Store.HOUR)
    endField.text = Store.formatDateTime(s ? s.end : now)
  }

  function pickProject(p) {
    projectId = p.id
    if (!session || session.project !== p.id) sheet = p.sheet
  }

  function nudge(field, minutes) {
    var t = Store.parseDateTime(field.text)
    if (!isNaN(t)) field.text = Store.formatDateTime(t + minutes * Store.MINUTE)
  }

  function save() {
    var start = Store.parseDateTime(startField.text)
    var end = Store.parseDateTime(endField.text)
    if (isNaN(start) || isNaN(end)) { error = "Use the format 2026-09-24 14:05"; return }
    if (end <= start) { error = "The end has to be after the start"; return }
    if (end > Date.now() + Store.MINUTE) { error = "That end is in the future"; return }
    if (!project) { error = "Pick a project"; return }
    var fields = { project: projectId, sheet: project.mode === "sheets" ? sheet : null, start: start, end: end }
    var ok = session ? service.updateSession(session.id, fields) : service.addSession(fields)
    if (!ok) { error = "Could not save that session"; return }
    done()
  }

  function handleKey(event) {
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { save(); event.accepted = true }
    else if (event.key === Qt.Key_Escape) { done(); event.accepted = true }
  }

  implicitHeight: form.implicitHeight + Style.space(24)
  radius: Style.cornerRadius
  color: Style.normalFillFor(look.fg, look.accent)
  borderSpec: Border.controlSpec("normal", look.fg, look.accent)

  Column {
    id: form
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.space(12)
    spacing: Style.space(10)

    Flow {
      width: parent.width
      spacing: Style.space(4)

      Repeater {
        model: root.projects

        Button {
          required property var modelData
          text: modelData.name
          selected: modelData.id === root.projectId
          foreground: root.look.fg
          fontFamily: root.look.font
          fontSize: Style.font.bodySmall
          onClicked: root.pickProject(modelData)
        }
      }
    }

    Row {
      visible: root.project !== null && root.project.mode === "sheets"
      spacing: Style.space(2)

      Label {
        look: root.look
        secondary: true
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(48)
        text: "Sheet"
      }

      Button {
        iconText: Glyphs.previous
        foreground: root.look.fg
        fontFamily: root.look.font
        enabled: root.sheet > 0
        opacity: enabled ? 1 : 0.3
        onClicked: root.sheet--
      }

      Label {
        look: root.look
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(32)
        horizontalAlignment: Text.AlignHCenter
        text: root.sheet
        font.bold: true
      }

      Button {
        iconText: Glyphs.next
        foreground: root.look.fg
        fontFamily: root.look.font
        onClicked: root.sheet++
      }
    }

    Row {
      spacing: Style.space(4)

      Label {
        look: root.look
        secondary: true
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(48)
        text: "From"
      }

      TextField {
        id: startField
        width: Style.space(170)
        foreground: root.look.fg
        font.family: root.look.font
        inputMethodHints: Qt.ImhPreferNumbers
        Keys.onPressed: function(event) { root.handleKey(event) }
        onTextEdited: root.error = ""
      }

      Button {
        text: "−5m"
        fontSize: Style.font.caption
        foreground: root.look.fg
        fontFamily: root.look.font
        onClicked: root.nudge(startField, -5)
      }

      Button {
        text: "+5m"
        fontSize: Style.font.caption
        foreground: root.look.fg
        fontFamily: root.look.font
        onClicked: root.nudge(startField, 5)
      }
    }

    Row {
      spacing: Style.space(4)

      Label {
        look: root.look
        secondary: true
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(48)
        text: "Until"
      }

      TextField {
        id: endField
        width: Style.space(170)
        foreground: root.look.fg
        font.family: root.look.font
        inputMethodHints: Qt.ImhPreferNumbers
        Keys.onPressed: function(event) { root.handleKey(event) }
        onTextEdited: root.error = ""
      }

      Button {
        text: "−5m"
        fontSize: Style.font.caption
        foreground: root.look.fg
        fontFamily: root.look.font
        onClicked: root.nudge(endField, -5)
      }

      Button {
        text: "+5m"
        fontSize: Style.font.caption
        foreground: root.look.fg
        fontFamily: root.look.font
        onClicked: root.nudge(endField, 5)
      }
    }

    Label {
      look: root.look
      visible: root.error !== ""
      text: root.error
      color: Color.urgent
      font.pixelSize: Style.font.caption
    }

    Item {
      width: parent.width
      height: saveButton.implicitHeight

      Button {
        visible: root.session !== null
        iconText: Glyphs.trash
        text: root.confirmDelete ? "Really delete?" : "Delete"
        foreground: root.confirmDelete ? Color.urgent : root.look.fg
        fontFamily: root.look.font
        onClicked: {
          if (!root.confirmDelete) { root.confirmDelete = true; return }
          root.service.deleteSession(root.session.id)
          root.done()
        }
      }

      Row {
        anchors.right: parent.right
        spacing: Style.space(6)

        Button {
          text: "Cancel"
          foreground: root.look.fg
          fontFamily: root.look.font
          onClicked: root.done()
        }

        Button {
          id: saveButton
          iconText: Glyphs.check
          text: root.session ? "Save" : "Add"
          bordered: true
          foreground: root.look.fg
          fontFamily: root.look.font
          onClicked: root.save()
        }
      }
    }
  }
}
