import QtQuick
import qs.Commons
import qs.Ui
import "../Store.js" as Store
import "../Stats.js" as Stats
import "../Glyphs.js" as Glyphs

// Every project, hidden ones included. The eye decides what shows up on the
// track tab, so last semester's courses can go without losing their data.
Column {
  id: root

  property var service: null
  property var look: null

  // The id being edited, "new" for the create form, "" for none.
  property string editingId: ""
  property bool inlineFocused: false
  readonly property bool editing: createForm.fieldFocused || inlineFocused

  readonly property var doc: service ? service.doc : Store.emptyDocument()
  readonly property var totals: Stats.byProject(doc.sessions)

  spacing: Style.space(8)

  function beginEdit(id) {
    inlineFocused = false
    editingId = id
    if (id === "new") createForm.load(null)
  }

  Item {
    width: parent.width
    height: newButton.implicitHeight

    Label {
      look: root.look
      secondary: true
      anchors.verticalCenter: parent.verticalCenter
      text: root.doc.projects.length + (root.doc.projects.length === 1 ? " project" : " projects")
        + " · " + root.doc.projects.filter(function(p) { return p.visible }).length + " shown"
    }

    Button {
      id: newButton
      anchors.right: parent.right
      iconText: Glyphs.plus
      text: "New project"
      bordered: true
      visible: root.editingId !== "new"
      foreground: root.look.fg
      fontFamily: root.look.font
      onClicked: root.beginEdit("new")
    }
  }

  ProjectEditor {
    id: createForm
    width: parent.width
    look: root.look
    service: root.service
    visible: root.editingId === "new"
    onDone: root.editingId = ""
  }

  Column {
    width: parent.width
    spacing: Style.space(2)

    Repeater {
      model: root.doc.projects

      Column {
        id: entry
        required property var modelData
        required property int index
        width: parent.width

        readonly property var project: modelData
        readonly property bool open: root.editingId === project.id

        BorderSurface {
          width: parent.width
          height: root.look.rowHeight
          radius: Style.cornerRadius
          color: rowMouse.containsMouse || entry.open ? Style.hoverFillFor(root.look.fg, root.look.accent) : "transparent"

          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.beginEdit(entry.open ? "" : entry.project.id)
          }

          Rectangle {
            id: swatch
            x: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(12)
            height: width
            radius: width / 2
            color: root.look.projectColor(entry.project)
            opacity: entry.project.visible ? 1 : 0.4
          }

          Column {
            anchors.left: swatch.right
            anchors.leftMargin: Style.space(10)
            anchors.right: buttons.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            opacity: entry.project.visible ? 1 : 0.55

            Label {
              look: root.look
              width: parent.width
              text: entry.project.name + (entry.project.short ? "  (" + entry.project.short + ")" : "")
              font.bold: true
            }

            Label {
              look: root.look
              secondary: true
              width: parent.width
              text: (entry.project.mode === "sheets" ? "Sheets · now on " + entry.project.sheet : "Counter")
                + " · " + Store.duration(root.totals[entry.project.id] || 0) + " total"
                + (entry.project.visible ? "" : " · hidden")
            }
          }

          Row {
            id: buttons
            anchors.right: parent.right
            anchors.rightMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Button {
              iconText: entry.project.visible ? Glyphs.eye : Glyphs.eyeOff
              foreground: root.look.fg
              fontFamily: root.look.font
              tooltipText: entry.project.visible ? "Shown on the track tab — click to hide" : "Hidden — click to show"
              onClicked: root.service.updateProject(entry.project.id, { visible: !entry.project.visible })
            }

            Button {
              iconText: Glyphs.up
              foreground: root.look.fg
              fontFamily: root.look.font
              enabled: entry.index > 0
              opacity: enabled ? 1 : 0.3
              tooltipText: "Move up"
              onClicked: root.service.moveProject(entry.project.id, -1)
            }

            Button {
              iconText: Glyphs.down
              foreground: root.look.fg
              fontFamily: root.look.font
              enabled: entry.index < root.doc.projects.length - 1
              opacity: enabled ? 1 : 0.3
              tooltipText: "Move down"
              onClicked: root.service.moveProject(entry.project.id, 1)
            }

            Button {
              iconText: Glyphs.pencil
              selected: entry.open
              foreground: root.look.fg
              fontFamily: root.look.font
              tooltipText: "Edit"
              onClicked: root.beginEdit(entry.open ? "" : entry.project.id)
            }
          }
        }

        Loader {
          width: parent.width
          active: entry.open
          sourceComponent: ProjectEditor {
            look: root.look
            service: root.service
            Component.onCompleted: load(entry.project)
            onDone: root.beginEdit("")
            onFieldFocusedChanged: root.inlineFocused = fieldFocused
          }
        }
      }
    }
  }

  // ---- Settings ----------------------------------------------------------------

  PanelSeparator {
    width: parent.width
    foreground: root.look.fg
  }

  SectionTitle {
    look: root.look
    text: "Settings"
  }

  Item {
    width: parent.width
    height: Math.max(dayText.implicitHeight, dayRow.implicitHeight)

    Column {
      id: dayText
      anchors.left: parent.left
      anchors.right: dayRow.left
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter

      Label { look: root.look; text: "A day starts at" }
      Label {
        look: root.look
        secondary: true
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Work after midnight counts towards the day it started on."
      }
    }

    Row {
      id: dayRow
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Button {
        iconText: Glyphs.previous
        foreground: root.look.fg
        fontFamily: root.look.font
        enabled: root.doc.settings.dayStartHour > 0
        opacity: enabled ? 1 : 0.3
        onClicked: root.service.setDayStartHour(root.doc.settings.dayStartHour - 1)
      }

      Label {
        look: root.look
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(52)
        horizontalAlignment: Text.AlignHCenter
        text: Store.pad2(root.doc.settings.dayStartHour) + ":00"
        font.bold: true
      }

      Button {
        iconText: Glyphs.next
        foreground: root.look.fg
        fontFamily: root.look.font
        enabled: root.doc.settings.dayStartHour < 12
        opacity: enabled ? 1 : 0.3
        onClicked: root.service.setDayStartHour(root.doc.settings.dayStartHour + 1)
      }
    }
  }

  Toggle {
    width: parent.width
    label: "Demo data"
    description: "A made-up semester to try the stats. Nothing is saved while it is on."
    checked: root.service ? root.service.demo : false
    foreground: root.look.fg
    fontFamily: root.look.font
    onClicked: root.service.setDemo(!root.service.demo)
  }

  Label {
    look: root.look
    secondary: true
    width: parent.width
    wrapMode: Text.WordWrap
    text: "Data: " + (root.service ? root.service.dataDir.replace(/^\/home\/[^/]+/, "~") : "") + "/data.json, with daily backups beside it"
  }
}
