import QtQuick
import qs.Commons
import qs.Ui
import "../Store.js" as Store
import "../Palette.js" as Palette
import "../Glyphs.js" as Glyphs

// Create / edit form for one project. Only the name needs the keyboard;
// everything else is clicks.
BorderSurface {
  id: root

  property var look: null
  property var service: null
  property var project: null   // null = create

  property string mode: "counter"
  property int sheet: 1
  property int colorSlot: 0
  property bool confirmDelete: false

  readonly property bool fieldFocused: nameField.activeFocus || shortField.activeFocus
  readonly property bool valid: nameField.text.trim() !== ""
  readonly property int sessionCount: project && service
    ? service.doc.sessions.filter(function(s) { return s.project === root.project.id }).length : 0

  signal done()

  onDone: { nameField.focus = false; shortField.focus = false }

  function load(p) {
    project = p
    confirmDelete = false
    nameField.text = p ? p.name : ""
    shortField.text = p ? p.short : ""
    mode = p ? p.mode : "counter"
    sheet = p ? p.sheet : 1
    colorSlot = p ? p.color : Store.nextColor(service.doc)
    if (!p) Qt.callLater(function() { nameField.forceActiveFocus() })
  }

  function save() {
    if (!valid) { nameField.forceActiveFocus(); return }
    var fields = { name: nameField.text.trim(), short: shortField.text.trim(), mode: mode, sheet: sheet, color: colorSlot }
    if (project) service.updateProject(project.id, fields)
    else service.addProject(fields)
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

    Row {
      width: parent.width
      spacing: Style.space(8)

      TextField {
        id: nameField
        width: parent.width - shortField.width - parent.spacing
        placeholderText: "Name, e.g. Optimization"
        foreground: root.look.fg
        font.family: root.look.font
        Keys.onPressed: function(event) { root.handleKey(event) }
      }

      TextField {
        id: shortField
        width: Style.space(130)
        placeholderText: nameField.text.trim() ? Store.shortName({ name: nameField.text.trim(), short: "" }) : "Short name"
        maximumLength: 8
        foreground: root.look.fg
        font.family: root.look.font
        Keys.onPressed: function(event) { root.handleKey(event) }
      }
    }

    Item {
      width: parent.width
      height: modeGroup.implicitHeight

      ButtonGroup {
        id: modeGroup
        focusable: false
        options: [
          { value: "counter", label: "Counter", icon: Glyphs.counter, tooltip: "One running total" },
          { value: "sheets", label: "With sheets", icon: Glyphs.sheet, tooltip: "Counts time per problem sheet" }
        ]
        value: root.mode
        foreground: root.look.fg
        fontFamily: root.look.font
        onChanged: function(v) { root.mode = v }
      }

      Row {
        visible: root.mode === "sheets"
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Label {
          look: root.look
          secondary: true
          anchors.verticalCenter: parent.verticalCenter
          text: "Current sheet"
          rightPadding: Style.space(6)
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
    }

    Row {
      spacing: Style.space(6)

      Label {
        look: root.look
        secondary: true
        anchors.verticalCenter: parent.verticalCenter
        text: "Colour"
        rightPadding: Style.space(6)
      }

      Repeater {
        model: Palette.NAMES.length

        Rectangle {
          required property int index
          width: Style.space(22)
          height: width
          radius: width / 2
          color: root.look.slotColor(index)
          border.width: root.colorSlot === index ? Style.space(2) : 0
          border.color: root.look.fg

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.colorSlot = parent.index
          }
        }
      }
    }

    Item {
      width: parent.width
      height: saveButton.implicitHeight

      Button {
        id: deleteButton
        visible: root.project !== null
        iconText: Glyphs.trash
        text: root.confirmDelete
          ? (root.sessionCount ? "Delete with " + root.sessionCount + " sessions?" : "Really delete?")
          : "Delete"
        foreground: root.confirmDelete ? Color.urgent : root.look.fg
        fontFamily: root.look.font
        tooltipText: "Hiding keeps the data; deleting removes the sessions too"
        onClicked: {
          if (!root.confirmDelete) { root.confirmDelete = true; return }
          root.service.deleteProject(root.project.id)
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
          text: root.project ? "Save" : "Create"
          bordered: true
          enabled: root.valid
          opacity: enabled ? 1 : 0.4
          foreground: root.look.fg
          fontFamily: root.look.font
          onClicked: root.save()
        }
      }
    }
  }
}
