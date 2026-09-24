import QtQuick
import qs.Commons
import qs.Ui
import "../Store.js" as Store
import "../Stats.js" as Stats
import "../Glyphs.js" as Glyphs
import "../charts"

// Numbers first, then the charts: hours per week, where the time went, time
// per sheet and when each sheet was done, the weekday x hour punchcard, the
// last days as a timeline, a calendar, and a few fun facts.
//
// Every chart answers hover through its section header rather than a
// floating tooltip, so the marks stay visible while reading the numbers.
Column {
  id: root

  property var service: null
  property var look: null
  readonly property bool editing: false

  property string range: "semester"
  property string projectFilter: ""

  // Charts are rebuilt from scratch on each change, so the clock that feeds
  // them ticks once a minute rather than every second.
  property real now: Date.now()
  Timer {
    interval: 60 * 1000
    repeat: true
    running: true
    onTriggered: root.now = Date.now()
  }

  readonly property var doc: service ? service.doc : Store.emptyDocument()
  readonly property int dsh: doc.settings.dayStartHour
  readonly property var all: Stats.withActive(doc.sessions, service ? service.active : null, now)
  readonly property var filtered: Stats.filterProject(all, projectFilter)

  readonly property real from: {
    if (range === "week") return Stats.weekStartOf(now, dsh)
    if (range === "month") return Stats.addDays(Stats.dayStartOf(now, dsh), -29, dsh)
    if (range === "semester") return semesterStart(now)
    return all.length ? Stats.dayStartOf(all[0].start, dsh) : Stats.dayStartOf(now, dsh)
  }
  readonly property real to: now + 1
  readonly property var scoped: Stats.clip(filtered, from, to)
  readonly property var facts: Stats.facts(scoped, dsh)
  readonly property var streak: Stats.streaks(Stats.perDay(filtered, dsh), now, dsh)

  readonly property var rangeOptions: [
    { value: "week", label: "This week" },
    { value: "month", label: "30 days" },
    { value: "semester", label: "Semester", tooltip: "Since 1 March or 1 October" },
    { value: "all", label: "All time" }
  ]

  // Projects that have any time at all, in list order.
  readonly property var trackedProjects: {
    var totals = Stats.byProject(doc.sessions)
    return doc.projects.filter(function(p) { return totals[p.id] > 0 || (root.service && root.service.active && root.service.active.project === p.id) })
  }

  // Austrian semesters: winter from 1 October, summer from 1 March.
  function semesterStart(ms) {
    var d = new Date(Stats.dayStartOf(ms, dsh))
    var y = d.getFullYear()
    var m = d.getMonth()
    if (m >= 9) return new Date(y, 9, 1, dsh).getTime()
    if (m >= 2) return new Date(y, 2, 1, dsh).getTime()
    return new Date(y - 1, 9, 1, dsh).getTime()
  }

  function projectById(id) {
    return Store.projectById(doc, id)
  }

  function colorFor(id) {
    return look.projectColor(projectById(id))
  }

  function partsReadout(parts) {
    return parts.filter(function(p) { return p.value > 0 })
      .sort(function(a, b) { return b.value - a.value })
      .map(function(p) { var pr = root.projectById(p.id); return (pr ? Store.shortName(pr) : "?") + " " + Store.duration(p.value) })
      .join(", ")
  }

  function refresh() {
    now = Date.now()
  }

  spacing: Style.space(16)

  // ---- Filters ---------------------------------------------------------------

  Column {
    width: parent.width
    spacing: Style.space(6)

    ButtonGroup {
      focusable: false
      options: root.rangeOptions
      value: root.range
      foreground: root.look.fg
      fontFamily: root.look.font
      fontSize: Style.font.bodySmall
      onChanged: function(v) { root.range = v }
    }

    Flow {
      width: parent.width
      spacing: Style.space(4)
      visible: root.trackedProjects.length > 1

      Button {
        text: "All projects"
        selected: root.projectFilter === ""
        foreground: root.look.fg
        fontFamily: root.look.font
        fontSize: Style.font.caption
        verticalPadding: Style.space(3)
        onClicked: root.projectFilter = ""
      }

      Repeater {
        model: root.trackedProjects

        Button {
          required property var modelData
          text: modelData.name
          selected: root.projectFilter === modelData.id
          foreground: root.look.fg
          fontFamily: root.look.font
          fontSize: Style.font.caption
          verticalPadding: Style.space(3)
          onClicked: root.projectFilter = root.projectFilter === modelData.id ? "" : modelData.id
        }
      }
    }
  }

  Label {
    visible: root.scoped.length === 0
    look: root.look
    secondary: true
    width: parent.width
    horizontalAlignment: Text.AlignHCenter
    topPadding: Style.space(24)
    bottomPadding: Style.space(24)
    text: root.doc.sessions.length ? "Nothing tracked in this range." : "No data yet. Track a session, or switch on the demo data under Projects."
  }

  // ---- Headline numbers -------------------------------------------------------

  Row {
    visible: root.scoped.length > 0
    width: parent.width
    spacing: Style.space(6)

    readonly property real tileWidth: (width - 3 * spacing) / 4

    Tile {
      width: parent.tileWidth
      value: Store.duration(root.facts.total)
      caption: "tracked"
    }

    Tile {
      width: parent.tileWidth
      value: String(root.facts.count)
      caption: "sessions · ⌀ " + Store.duration(root.facts.average)
    }

    Tile {
      width: parent.tileWidth
      value: String(root.facts.activeDays)
      caption: "days · ⌀ " + Store.duration(root.facts.perActiveDay)
    }

    Tile {
      width: parent.tileWidth
      value: root.streak.current + (root.streak.current === 1 ? " day" : " days")
      caption: "streak · best " + root.streak.longest
    }
  }

  // ---- Hours per week ----------------------------------------------------------

  Column {
    visible: root.scoped.length > 0
    width: parent.width
    spacing: Style.space(6)

    readonly property int weekCount: {
      var weeks = Math.ceil((root.now - Stats.weekStartOf(root.from, root.dsh)) / (7 * Store.DAY))
      return Math.max(8, Math.min(26, weeks))
    }
    readonly property var weeks: Stats.weeklySeries(root.filtered, weekCount, root.now, root.dsh)
    readonly property var series: weeks.map(function(w) {
      var parts = []
      for (var i = 0; i < root.doc.projects.length; i++) {
        var id = root.doc.projects[i].id
        if (w.projects[id]) parts.push({ id: id, value: w.projects[id] })
      }
      return {
        label: Qt.formatDate(new Date(w.start), "d.M"),
        parts: parts,
        readout: "Week of " + Qt.formatDate(new Date(w.start), "d MMM") + " · " + Store.duration(w.total)
          + (parts.length > 1 ? " · " + root.partsReadout(parts) : "")
      }
    })

    SectionTitle {
      look: root.look
      text: "Hours per week"
      detail: weekBars.readout || ("⌀ " + Store.duration(Stats.total(Stats.clip(root.filtered, Stats.weekStartOf(root.from, root.dsh), root.to)) / Math.max(1, parent.weekCount)) + " a week")
    }

    Bars {
      id: weekBars
      width: parent.width
      height: Style.space(150)
      look: root.look
      series: parent.series
      colorFor: root.colorFor
    }
  }

  // ---- Share ---------------------------------------------------------------------

  Column {
    visible: root.projectFilter === "" && entries.length > 1
    width: parent.width
    spacing: Style.space(6)

    readonly property var entries: {
      var totals = Stats.byProject(root.scoped)
      var out = []
      for (var id in totals) {
        var p = root.projectById(id)
        if (p) out.push({ project: p, value: totals[id] })
      }
      out.sort(function(a, b) { return b.value - a.value })
      return out
    }

    SectionTitle {
      look: root.look
      text: "Where the time went"
      detail: share.readout
    }

    ShareBar {
      id: share
      width: parent.width
      look: root.look
      entries: parent.entries
    }
  }

  // ---- Sheets ----------------------------------------------------------------------

  Repeater {
    model: root.doc.projects.filter(function(p) {
      if (p.mode !== "sheets") return false
      if (root.projectFilter && root.projectFilter !== p.id) return false
      return root.scoped.some(function(s) { return s.project === p.id && s.sheet !== null })
    })

    Column {
      id: sheetBlock
      required property var modelData
      width: root.width
      spacing: Style.space(6)

      readonly property var project: modelData
      readonly property var own: Stats.filterProject(root.scoped, project.id)
      readonly property var sheets: Stats.sheets(own, project.id, root.dsh)
      readonly property real average: {
        var done = sheets.filter(function(s) { return s.sheet < sheetBlock.project.sheet })
        var sum = 0
        for (var i = 0; i < done.length; i++) sum += done[i].total
        return done.length ? sum / done.length : 0
      }
      readonly property var series: sheets.map(function(s) {
        return {
          label: String(s.sheet),
          parts: [{ id: sheetBlock.project.id, value: s.total }],
          readout: "Sheet " + s.sheet + " · " + Store.duration(s.total) + " · " + s.count + (s.count === 1 ? " session" : " sessions")
            + " on " + s.days + (s.days === 1 ? " day" : " days")
            + " · " + Qt.formatDate(new Date(s.first), "d MMM") + (s.days > 1 ? "–" + Qt.formatDate(new Date(s.last), "d MMM") : "")
        }
      })

      SectionTitle {
        look: root.look
        text: sheetBlock.project.name + " · time per sheet"
        detail: sheetBars.readout || (sheetBlock.average > 0 ? "⌀ " + Store.duration(sheetBlock.average) + " per finished sheet" : "")
      }

      Bars {
        id: sheetBars
        width: parent.width
        height: Style.space(120)
        look: root.look
        series: sheetBlock.series
        colorFor: root.colorFor
        reference: sheetBlock.average
        referenceLabel: sheetBlock.average > 0 ? "⌀" : ""
      }

      SectionTitle {
        look: root.look
        text: "When each sheet was done"
        detail: sheetDays.readout
      }

      SheetTimeline {
        id: sheetDays
        width: parent.width
        look: root.look
        project: sheetBlock.project
        sessions: sheetBlock.own
        // From the first touched sheet, not the start of the range: a
        // semester that began weeks before the course would only add air.
        from: sheetBlock.sheets.length
          ? Math.max(root.from, Math.min.apply(null, sheetBlock.sheets.map(function(s) { return s.first })))
          : root.from
        to: root.to
        dayStartHour: root.dsh
      }
    }
  }

  // ---- Punchcard ---------------------------------------------------------------------

  Column {
    visible: root.scoped.length > 0
    width: parent.width
    spacing: Style.space(6)

    SectionTitle {
      look: root.look
      text: "Punchcard"
      detail: punchcard.readout || (root.facts.busiestHour >= 0
        ? "busiest: " + ["Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays", "Saturdays", "Sundays"][root.facts.busiestWeekday]
          + " around " + Store.pad2(root.facts.busiestHour) + ":00"
        : "")
    }

    Punchcard {
      id: punchcard
      width: parent.width
      look: root.look
      grid: Stats.punchcard(root.scoped)
    }
  }

  // ---- Recent days -----------------------------------------------------------------

  Column {
    visible: root.filtered.length > 0
    width: parent.width
    spacing: Style.space(6)

    readonly property int dayCount: root.range === "week" ? 7 : 14

    SectionTitle {
      look: root.look
      text: "Last " + parent.dayCount + " days"
      detail: timeline.readout
    }

    Timeline {
      id: timeline
      width: parent.width
      look: root.look
      lanes: Stats.timeline(root.filtered, parent.dayCount, root.now, root.dsh)
      projectFor: root.projectById
      dayStartHour: root.dsh
    }
  }

  // ---- Calendar ----------------------------------------------------------------------

  Column {
    visible: root.filtered.length > 0
    width: parent.width
    spacing: Style.space(6)

    readonly property var days: {
      var today = Stats.dayStartOf(root.now, root.dsh)
      // Whole weeks: back to a Monday, 20 weeks ago.
      var count = 19 * 7 + Stats.weekday(today) + 1
      return Stats.dailySeries(root.filtered, count, root.now, root.dsh)
    }

    SectionTitle {
      look: root.look
      text: "Calendar · 20 weeks"
      detail: calendar.readout
    }

    Calendar {
      id: calendar
      width: parent.width
      look: root.look
      days: parent.days
      dayStartHour: root.dsh
    }
  }

  // ---- Facts ---------------------------------------------------------------------------

  Column {
    visible: root.scoped.length > 0
    width: parent.width
    spacing: Style.space(6)

    SectionTitle {
      look: root.look
      text: "Fun facts"
    }

    Grid {
      width: parent.width
      columns: 2
      columnSpacing: Style.space(24)
      rowSpacing: Style.space(4)

      readonly property var f: root.facts
      readonly property real half: (width - columnSpacing) / 2
      readonly property var items: {
        if (!f.count) return []
        var list = []
        if (f.longest) {
          var lp = root.projectById(f.longest.project)
          list.push(["Longest session", Store.duration(f.longest.end - f.longest.start) + " · " + (lp ? Store.shortName(lp) : "")
            + " · " + Qt.formatDate(new Date(f.longest.start), "d MMM")])
        }
        if (f.longestDay) list.push(["Longest day", Store.duration(f.longestDay.total) + " · " + Qt.formatDate(new Date(f.longestDay.start), "ddd d MMM")])
        list.push(["Typical session", Store.duration(f.median) + " (median)"])
        if (f.earliest) list.push(["Earliest start", Store.timeOfDay(f.earliest.at) + " · " + Qt.formatDate(new Date(f.earliest.at), "d MMM")])
        if (f.latest) list.push(["Latest finish", Store.timeOfDay(f.latest.at) + " · " + Qt.formatDate(new Date(f.latest.at), "d MMM")])
        list.push([Glyphs.night + " Night owl", Math.round(100 * f.nightShare) + "% after 22:00"])
        list.push(["Weekend share", Math.round(100 * f.weekendShare) + "%"])
        var auto = root.scoped.filter(function(s) { return s.stop === "lock" || s.stop === "suspend" }).length
        list.push(["Stopped by lock", auto + " of " + f.count + " sessions"])
        return list
      }

      Repeater {
        model: parent.items

        Row {
          required property var modelData
          width: parent.half
          spacing: Style.space(8)

          Label {
            look: root.look
            secondary: true
            width: Style.space(110)
            text: modelData[0]
          }

          Label {
            look: root.look
            width: parent.width - Style.space(118)
            text: modelData[1]
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }

  // Headline number with a caption underneath.
  component Tile: BorderSurface {
    id: tile
    property string value: ""
    property string caption: ""
    height: tileColumn.implicitHeight + Style.space(16)
    radius: Style.cornerRadius
    color: Style.normalFillFor(root.look.fg, root.look.accent)
    borderSpec: Border.controlSpec("normal", root.look.fg, root.look.accent)

    Column {
      id: tileColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(2)

      Label {
        look: root.look
        width: parent.width
        text: tile.value
        font.pixelSize: Style.font.heading
        font.bold: true
      }

      Label {
        look: root.look
        secondary: true
        width: parent.width
        text: tile.caption
      }
    }
  }
}
