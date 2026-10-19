import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The clock's calendar popup: a month grid with ISO week numbers, built to
// sit beside the weather panel — same hero-over-detail composition, same
// spacing scale, same small-caps labels.
//
// OmaJournal adds your Obsidian daily notes: each day with a note gets the
// same dots Obsidian's Calendar shows (one per 250 words, a hollow one for
// open to-dos). Click a day to see its to-dos and journal under the grid,
// double-click it to open the note in Obsidian. helpers/omajournalctl does
// all the reading and writing.
//
// BarWidget.qml owns the bar label and hands this panel the button to
// anchor against.
Panel {
  id: root
  moduleName: "omarchy.clock"
  ipcTarget: "omarchy.clock"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Today. SystemClock keeps this honest across midnight so the
  //      highlight rolls over without the panel being reopened.
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)

  // The month on screen. Stepping moves this and nothing else: the grid is
  // a read-out, not a picker, so there is no per-day cursor to keep in sync.
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()

  // Local noon, so a first of the month with no midnight (Havana, April 2012)
  // still names its own month; UTC would name the previous one west of Greenwich.
  readonly property date viewDate: new Date(viewYear, viewMonth, 1, 12)
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()

  // Pinned to today, not to the month being browsed — stepping through the
  // calendar does not change how much of the year is gone.
  readonly property real yearDone: Model.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int yearDonePercent: Model.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())

  // Memento mori, for anyone who goes looking: double-tapping the year bar
  // asks for a birth year and a life expectancy, and a second bar tracks one
  // against the other. A birth year rather than an age, so it keeps counting
  // on its own. Without one the bar stays hidden.
  readonly property int birthYear: Model.parseBirthYear(setting("birthYear", 0), today.getFullYear())
  readonly property int age: Model.ageFromBirthYear(birthYear, today.getFullYear())
  readonly property int lifeExpectancy: Model.parseLifeExpectancy(setting("lifeExpectancy", 0))
  readonly property real lifeDone: Model.lifeProgress(age, lifeExpectancy)
  readonly property int lifeDonePercent: Model.lifeProgressPercent(age, lifeExpectancy)
  property bool editingLife: false

  // Unset falls through to the locale's own first day, so a fresh install
  // starts out matching the rest of the desktop rather than a hardcoded
  // convention. Clicking the grid's "W" heading writes the choice back to
  // shell.json.
  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
  // The interface is English throughout, so day names are not taken from the
  // system locale. Where the week starts still is: that is a regional
  // convention rather than a translation, and it stays overridable above.
  readonly property var labelLocale: Qt.locale("en_US")
  readonly property string nextWeekStartLabel: labelLocale.dayName(Model.toggledWeekStart(weekStart), Locale.LongFormat)
  readonly property var weekdays: Model.weekdayOrder(weekStart)
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey)


  // Guarded so the widget renders before the bar is injected (the bar-widget
  // contract instantiates it bare).
  readonly property color contentForeground: bar ? bar.foreground : Commons.Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  // ---- Daily notes. monthNotes maps "YYYY-MM-DD" to that note's counts for
  //      the month on screen; dayNote is the selected day in full.
  readonly property string helperPath: decodeURIComponent(Qt.resolvedUrl("helpers/omajournalctl").toString().replace(/^file:\/\//, ""))
  readonly property string vaultPath: String(setting("vaultPath", "") || "")
  property var monthNotes: ({})
  property string selectedKey: todayKey
  property var dayNote: null
  property string journalError: ""
  readonly property date selectedDate: Model.dateFromKey(selectedKey)
  readonly property var todoList: dayNote && dayNote.todoList ? dayNote.todoList : []
  readonly property var journalLines: dayNote && dayNote.journal ? dayNote.journal : []
  readonly property int journalPreviewCount: 4

  function helper(args) {
    var command = ["timeout", "-k", "2", "8", "python3", "-B", "-I", root.helperPath]
    if (root.vaultPath !== "") command = command.concat(["--vault", root.vaultPath])
    return command.concat(args)
  }

  function monthKey() {
    return viewYear + "-" + Model.pad2(viewMonth + 1)
  }

  function loadMonth() {
    monthProcess.running = false
    monthProcess.command = helper(["month", monthKey()])
    monthProcess.running = true
  }

  function loadDay() {
    dayProcess.running = false
    dayProcess.command = helper(["day", root.selectedKey])
    dayProcess.running = true
  }

  function reloadJournal() {
    loadMonth()
    loadDay()
  }

  function selectDay(cell) {
    root.selectedKey = cell.key
    if (!cell.inMonth) {
      root.viewYear = cell.year
      root.viewMonth = cell.month
      loadMonth()
    }
    loadDay()
  }

  // Jump to a day by "YYYY-MM-DD" (the IPC `day` call uses this).
  function selectKey(key) {
    var date = Model.dateFromKey(key)
    if (Model.keyForDate(date) !== String(key)) return
    root.selectDay({ key: String(key), year: date.getFullYear(), month: date.getMonth(), inMonth: date.getFullYear() === root.viewYear && date.getMonth() === root.viewMonth })
  }

  function openNote(key) {
    if (root.dayNote && root.dayNote.date === key && root.dayNote.uri) {
      Qt.openUrlExternally(root.dayNote.uri)
      root.close()
      return
    }
    // Not loaded yet: ask the helper for the link, then open it.
    openProcess.running = false
    openProcess.command = helper(["day", key])
    openProcess.running = true
  }

  function runEdit(args, stdinText) {
    if (editProcess.running) return
    root.journalError = ""
    editProcess.pending = stdinText || ""
    editProcess.command = helper(args)
    editProcess.running = true
  }

  function toggleTodo(item) {
    if (!root.dayNote || !root.dayNote.hash) return
    runEdit(["toggle", root.selectedKey, String(item.line), root.dayNote.hash])
  }

  function addTodo(text) {
    var clean = String(text || "").replace(/[\r\n]+/g, " ").trim()
    if (clean === "" || !root.dayNote || !root.dayNote.hash) return
    runEdit(["add", root.selectedKey, root.dayNote.hash], clean)
  }

  function addNote(text) {
    var clean = String(text || "").replace(/[\r\n]+/g, " ").trim()
    if (clean === "" || !root.dayNote || !root.dayNote.hash) return
    runEdit(["note", root.selectedKey, root.dayNote.hash], clean)
  }

  function createNote() {
    runEdit(["create", root.selectedKey])
  }

  function parseResult(text) {
    try {
      return JSON.parse(String(text || "").trim() || "{}")
    } catch (e) {
      return { ok: false, error: "Couldn't read your notes" }
    }
  }

  readonly property int cellWidth: Style.space(52)
  readonly property int cellHeight: Style.space(42)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(32)
  readonly property int gutterWidth: Style.space(14)

  function open() {
    refresh()
    root.controller.show()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears the
    // shared flag. Deferring means the panel taking over always wins, while
    // a handoff to a panel that does not manage the flag still leaves it
    // cleared rather than stuck on.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    // Dismissing the panel mid-edit would otherwise leave the inputs up,
    // waiting behind a closed popup for the next time it opens.
    if (root.editingLife) root.cancelEditingLife()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Summoning by hotkey moves no pointer, so a hover the bar was still
  // holding must not keep the center indicators revealed behind the panel.
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    root.today = new Date()
    root.goToToday()
  }

  // Back to this month with today picked.
  function goToToday() {
    root.viewYear = today.getFullYear()
    root.viewMonth = today.getMonth()
    root.selectedKey = root.todayKey
    loadMonth()
    loadDay()
  }

  function moveMonth(delta) {
    var next = Model.stepMonth(viewYear, viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
    loadMonth()
  }

  function moveYear(delta) {
    moveMonth(delta * 12)
  }

  // Applied locally first so the panel redraws on the click itself; the
  // shell.json write comes back through the bar as the same value. With no
  // writable entry (the widget is not in the layout) it stays a session-only
  // preference rather than doing nothing. The host widget builds its own
  // entry when the label format is cycled, so it has to be kept in step or
  // it would write this key straight back out from a stale copy.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setWeekStart(day) {
    var next = Model.normalizedWeekStart(day, root.weekStart)
    if (next === root.weekStart) return
    persistSettings({ weekStartDay: Model.weekStartSettingName(next) })
  }

  function startEditingLife() {
    root.editingLife = true
    Qt.callLater(function() {
      bornField.text = root.birthYear > 0 ? String(root.birthYear) : ""
      expectancyField.text = String(root.lifeExpectancy)
      bornField.selectAll()
      bornField.forceActiveFocus()
    })
  }

  function cancelEditingLife() {
    root.editingLife = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  // Shared by both fields: Tab hops to the other one, Enter commits the pair,
  // Escape drops the lot.
  function handleLifeKey(event, other) {
    if (event.key === Qt.Key_Escape) {
      root.cancelEditingLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.commitLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      other.selectAll()
      other.forceActiveFocus()
      event.accepted = true
    }
  }

  // Double-tapping the life bar puts it away again. The expectancy stays in
  // the config so setting a birth year again brings your own number back
  // rather than the default.
  function clearLife() {
    if (root.birthYear <= 0) return
    persistSettings({ birthYear: 0 })
  }

  function commitLife() {
    var born = Model.parseBirthYear(bornField.text, today.getFullYear())
    var span = Model.parseLifeExpectancy(expectancyField.text)
    if (born !== root.birthYear || span !== root.lifeExpectancy)
      persistSettings({ birthYear: born, lifeExpectancy: span })
    cancelEditingLife()
  }

  function toggleWeekStart() {
    setWeekStart(Model.toggledWeekStart(root.weekStart))
  }

  // English short day names, matching the rest of the interface.
  function weekdayLabel(weekday) {
    return String(labelLocale.dayName(weekday, Locale.ShortFormat)).toUpperCase()
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      if (Model.keyForDate(clock.date) === String(root.todayKey)) return
      var followToday = root.viewingCurrentMonth
      root.today = clock.date
      if (followToday) root.goToToday()
    }
  }

  // ---- Helper runs. Each prints one small JSON object; the helper caps
  //      what it reads and how much it prints, and `timeout` caps how long.
  Process {
    id: monthProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var result = root.parseResult(text)
        if (result.ok && result.month === root.monthKey()) root.monthNotes = result.days || ({})
        else if (!result.ok) root.journalError = result.error || ""
      }
    }
  }

  Process {
    id: dayProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var result = root.parseResult(text)
        if (result.ok && result.date === root.selectedKey) {
          root.dayNote = result
          root.journalError = ""
        } else if (!result.ok) {
          root.journalError = result.error || ""
        }
      }
    }
  }

  Process {
    id: openProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var result = root.parseResult(text)
        if (result.ok && result.exists && result.uri) {
          Qt.openUrlExternally(result.uri)
          root.close()
        } else if (result.ok) {
          root.journalError = "No note for this day yet. Use Make note."
        } else {
          root.journalError = result.error || ""
        }
      }
    }
  }

  // Edits answer with the day's note as it is afterwards. A typed to-do goes
  // over stdin, never on the command line.
  Process {
    id: editProcess
    property string pending: ""
    stdinEnabled: true
    onStarted: {
      if (pending !== "") write(pending + "\n")
      pending = ""
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var result = root.parseResult(text)
        if (result.ok && result.date === root.selectedKey) {
          root.dayNote = result
          root.journalError = ""
        } else if (!result.ok) {
          root.journalError = result.error || ""
          root.loadDay()
        }
        root.loadMonth()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(calendarColumn.implicitHeight)

    NameBackdrop {
      copyWidth: 0.55
      strength: 0.12
      fontFamily: root.contentFontFamily
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingLife || addField.activeFocus || noteField.activeFocus
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.moveMonth(dx)
        if (dy !== 0) root.moveYear(dy)
      }
      onActivateRequested: root.goToToday()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "[") root.moveMonth(-1)
        else if (t === "]") root.moveMonth(1)
        else if (t === "{") root.moveYear(-1)
        else if (t === "}") root.moveYear(1)
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "w" || t === "W") root.toggleWeekStart()
        else if (t === "o" || t === "O") root.openNote(root.selectedKey)
      }

      Flickable {
        id: calendarScroll
        anchors.fill: parent
        contentWidth: calendarColumn.width
        contentHeight: calendarColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height || contentWidth > width

        Column {
          id: calendarColumn
          // Never narrower than the grid. The popup width is capped to what
          // the screen allows, and a fixed seven-column grid would otherwise
          // lose its last days off the edge instead of scrolling.
          width: Math.max(calendarScroll.width, gridColumn.width)
          spacing: Style.space(8)

          // ---- Hero: today, centered. Once the view has stepped back
          //      it is also the way home — clicking the date you are
          //      looking for beats hunting for a reset button.
          Item {
            width: parent.width
            height: heroRow.height

            Row {
              id: heroRow
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(22)

              Text {
                textFormat: Text.PlainText
                // Baseline-aligned, not center-aligned: "July 26" carries a
                // descender, so centering the two boxes leaves the icon
                // sitting visibly low against the digits.
                anchors.baseline: heroDate.baseline
                text: "󰃭"
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Commons.Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                // Decorative, and deliberately outside the Style.font.*
                // scale. Sized so the glyph reads at the cap height of the
                // date beside it rather than towering over it.
                font.pixelSize: 48
              }

              Text {
                id: heroDate
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDate(root.today, "MMMM d")
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Commons.Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: 52
                font.bold: true
              }
            }

            MouseArea {
              id: heroMouse
              x: heroRow.x
              y: heroRow.y
              width: heroRow.width
              height: heroRow.height
              enabled: !root.viewingCurrentMonth
              hoverEnabled: enabled
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToToday()

              PanelToolTip {
                visible: heroMouse.containsMouse
                text: "Back to today"
                fontFamily: root.contentFontFamily
              }
            }
          }

          // ---- Year progress, doubling as the rule under the hero:
          //      a plain hairline said nothing, and whole days done
          //      over days in the year says the same thing louder.
          Item {
            width: parent.width
            height: yearBlock.y + yearBlock.height

            Item {
              id: yearBlock
              y: Style.space(6)
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(yearLabel.implicitHeight, Style.space(10))

              TapHandler {
                enabled: !root.editingLife
                onDoubleTapped: root.startEditingLife()
              }

              Row {
                visible: root.editingLife
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  text: "BORN"
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                TextField {
                  id: bornField
                  width: Style.space(70)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: "year"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly

                  Keys.onPressed: function(event) { root.handleLifeKey(event, expectancyField) }
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.verticalCenterOffset: 0
                  leftPadding: Style.space(6)
                  text: "LIVE TO"
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                TextField {
                  id: expectancyField
                  width: Style.space(60)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: "90"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly

                  Keys.onPressed: function(event) { root.handleLifeKey(event, bornField) }
                }
              }

              Text {
                id: yearLabel
                textFormat: Text.PlainText
                visible: !root.editingLife
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.today.getFullYear()
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Text {
                id: yearPercent
                textFormat: Text.PlainText
                visible: !root.editingLife
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.yearDonePercent + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                id: yearTrack
                visible: !root.editingLife
                anchors.left: yearLabel.right
                anchors.right: yearPercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: Math.round(parent.width * root.yearDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Commons.Color.accent)

                  Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
              }
            }
          }

          // ---- Memento mori. Only here once someone has gone looking and
          //      given an age; the same rail as the year above it, measured
          //      against a nominal lifetime.
          Item {
            visible: root.birthYear > 0
            width: parent.width
            height: visible ? lifeBlock.height : 0

            Item {
              id: lifeBlock
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(lifeLabel.implicitHeight, Style.space(10))

              Text {
                textFormat: Text.PlainText
                id: lifeLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "LIFE"
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Text {
                id: lifePercent
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.lifeDonePercent + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                anchors.left: lifeLabel.right
                anchors.right: lifePercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: Math.round(parent.width * root.lifeDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Commons.Color.accent)

                  Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
              }

              TapHandler {
                onDoubleTapped: root.clearLife()
              }

              MouseArea {
                id: lifeMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton

                PanelToolTip {
                  visible: lifeMouse.containsMouse
                  text: "Memento Mori"
                  fontFamily: root.contentFontFamily
                }
              }
            }
          }

          // ---- Month grid: week numbers down a gutter on the left, then
          //      the seven day columns. Always six rows, so the popup is
          //      exactly as tall in February as it is in August.
          Item {
            width: parent.width
            height: gridColumn.y + gridColumn.height

            WheelHandler {
              onWheel: function(event) {
                // Horizontal wheels and touchpad side-scrolls report y === 0;
                // without this they would every one read as "next month".
                if (event.angleDelta.y === 0) return
                root.moveMonth(event.angleDelta.y > 0 ? -1 : 1)
              }
            }

            Column {
              id: gridColumn
              // The meter above is a solid rule; the grid needs room to
              // read as its own block rather than hanging off it.
              y: Style.space(18)
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(3)

              Row {
                id: headerRow
                spacing: root.cellSpacing

                // The week-number heading doubles as the week-start toggle.
                // It is the one control in the panel whose meaning is not
                // self-evident, so it carries a tooltip naming the day the
                // click will switch to.
                Rectangle {
                  width: root.weekColumnWidth
                  height: Style.space(16)
                  radius: Style.cornerRadius
                  color: weekStartMouse.containsMouse
                    ? Style.hoverFillFor(root.contentForeground, Commons.Color.accent)
                    : "transparent"

                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: "W"
                    color: weekStartMouse.containsMouse
                      ? Style.hoverStateColor(root.contentForeground, Commons.Color.accent)
                      : Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }

                  MouseArea {
                    id: weekStartMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleWeekStart()
                  }

                  PanelToolTip {
                    visible: weekStartMouse.containsMouse
                    text: "Start weeks on " + root.nextWeekStartLabel
                    fontFamily: root.contentFontFamily
                  }
                }

                Item {
                  width: root.gutterWidth
                  height: Style.space(16)
                }

                Repeater {
                  model: root.weekdays

                  Text {
                    textFormat: Text.PlainText
                    required property var modelData
                    width: root.cellWidth
                    height: Style.space(16)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.weekdayLabel(modelData)
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }
                }
              }

              Repeater {
                model: root.weeks

                Row {
                  required property var modelData
                  spacing: root.cellSpacing

                  Text {
                    textFormat: Text.PlainText
                    width: root.weekColumnWidth
                    height: root.cellHeight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.week
                    color: Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Item {
                    width: root.gutterWidth
                    height: root.cellHeight
                  }

                  Repeater {
                    model: modelData.days

                    Rectangle {
                      id: dayCell
                      required property var modelData
                      readonly property var note: root.monthNotes[modelData.key] || null
                      readonly property bool selected: modelData.key === root.selectedKey

                      width: root.cellWidth
                      height: root.cellHeight
                      radius: Style.cornerRadius
                      // Today is outlined, not filled: a lit-up block shouts
                      // over a grid this quiet. The picked day gets a soft fill.
                      color: selected
                        ? Style.selectedFillFor(root.contentForeground, Commons.Color.accent)
                        : (dayMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Commons.Color.accent) : "transparent")
                      border.width: modelData.today ? Style.spacing.hairline : 0
                      border.color: Style.normalBorderFor(root.contentForeground, Commons.Color.accent)

                      Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.InOutQuad } }

                      Text {
                        textFormat: Text.PlainText
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -Style.space(5)
                        text: dayCell.modelData.day
                        color: dayCell.modelData.inMonth
                          ? (dayCell.modelData.weekend ? Qt.darker(root.contentForeground, 1.45) : root.contentForeground)
                          : Qt.darker(root.contentForeground, 2.2)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.body
                        font.bold: dayCell.modelData.today
                      }

                      // Obsidian's Calendar dots: filled per 250 words, then
                      // a hollow one when the note has open to-dos.
                      Row {
                        visible: dayCell.note !== null
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Style.space(6)
                        spacing: Style.space(3)

                        Repeater {
                          model: dayCell.note ? dayCell.note.dots : 0

                          Rectangle {
                            width: Style.space(4)
                            height: width
                            radius: width / 2
                            color: dayCell.modelData.inMonth ? root.contentForeground : Qt.darker(root.contentForeground, 2.2)
                            opacity: 0.75
                          }
                        }

                        Rectangle {
                          visible: dayCell.note !== null && dayCell.note.openTasks === true
                          width: Style.space(4)
                          height: width
                          radius: width / 2
                          color: "transparent"
                          border.width: 1
                          border.color: root.contentForeground
                          opacity: 0.75
                        }
                      }

                      MouseArea {
                        id: dayMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectDay(dayCell.modelData)
                        onDoubleClicked: root.openNote(dayCell.modelData.key)
                      }
                    }
                  }
                }
              }
            }

            // Hairline down the week-number gutter, drawn only beside the
            // day rows so it does not cut through the header band.
            Rectangle {
              x: gridColumn.x + root.weekColumnWidth + root.cellSpacing + Math.round((root.gutterWidth - width) / 2)
              y: gridColumn.y + headerRow.height + gridColumn.spacing
              width: Style.spacing.hairline
              height: gridColumn.height - headerRow.height - gridColumn.spacing
              color: root.contentForeground
              opacity: 0.1
            }
          }

          // ---- Month stepping, spanning the grid it drives. The chevrons
          //      sit on the grid's outer bounds, the same edges the year
          //      rail above uses, so the row reads as the panel's other
          //      full-width rail instead of a cluster floating in space.
          //      The label is centered and fixed-width, so it holds still
          //      from "MAY" to "SEPTEMBER".
          Item {
            width: parent.width
            height: monthNav.height

            Item {
              id: monthNav
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: monthLabel.implicitHeight + Style.space(10)

              Text {
                id: monthLabel
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                // Fixed width so the chevrons hold still between a
                // "MAY 2026" and a "SEPTEMBER 2026".
                width: Style.space(130)
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatDate(root.viewDate, "MMMM yyyy").toUpperCase()
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.letterSpacing: 1
              }

              PanelActionButton {
                // Pulled out by the button's own padding so the glyph, not
                // its hit box, lines up with the "2026" on the year rail.
                anchors.left: parent.left
                anchors.leftMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅁"
                tooltipText: "Previous month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(-1)
              }

              PanelActionButton {
                anchors.right: parent.right
                anchors.rightMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅂"
                tooltipText: "Next month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(1)
              }
            }
          }

          // ---- The picked day's note: to-dos you can tick, a box to add
          //      one, and the first lines of the journal.
          Item {
            width: parent.width
            height: dayColumn.implicitHeight

            Column {
              id: dayColumn
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              spacing: Style.space(8)

              PanelSeparator {
                width: parent.width
                foreground: root.contentForeground
              }

              Item {
                width: parent.width
                height: Math.max(dayTitle.implicitHeight, openButton.height)

                Column {
                  anchors.left: parent.left
                  anchors.right: openButton.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  Text {
                    id: dayTitle
                    width: parent.width
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    text: Qt.formatDate(root.selectedDate, "dddd, MMMM d")
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                  }

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    visible: text !== ""
                    text: {
                      if (!root.dayNote || root.dayNote.date !== root.selectedKey) return ""
                      if (!root.dayNote.exists) return "No note for this day"
                      var parts = []
                      if (root.dayNote.todos > 0) parts.push(root.dayNote.done + "/" + root.dayNote.todos + " done")
                      parts.push(root.dayNote.words + (root.dayNote.words === 1 ? " word" : " words"))
                      return parts.join(" · ")
                    }
                    color: Qt.darker(root.contentForeground, 1.4)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                PanelActionButton {
                  id: openButton
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  visible: root.dayNote !== null && root.dayNote.exists === true
                  iconText: "󰏌"
                  tooltipText: "Open in Obsidian"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.openNote(root.selectedKey)
                }
              }

              Button {
                visible: root.dayNote !== null && root.dayNote.date === root.selectedKey && root.dayNote.exists === false
                text: "Make note"
                iconText: "󰎔"
                bordered: true
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                enabled: !editProcess.running
                onClicked: root.createNote()
              }

              PanelSectionHeader {
                visible: root.todoList.length > 0 || addField.visible
                topPadding: Style.space(4)
                text: "TO DO"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
              }

              Repeater {
                model: root.todoList

                CursorSurface {
                  id: todoRow
                  required property var modelData
                  width: dayColumn.width
                  height: todoText.implicitHeight + Style.space(10)
                  foreground: root.contentForeground
                  hasCursor: todoMouse.containsMouse

                  Text {
                    id: todoBox
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(6) + todoRow.modelData.indent * Style.space(16)
                    anchors.top: parent.top
                    anchors.topMargin: Style.space(5)
                    textFormat: Text.PlainText
                    text: todoRow.modelData.done ? "󰄵" : "󰄱"
                    color: todoRow.modelData.done
                      ? Style.selectedStateColor(root.contentForeground, Commons.Color.accent)
                      : root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.icon
                  }

                  Text {
                    id: todoText
                    anchors.left: todoBox.right
                    anchors.leftMargin: Style.space(8)
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(6)
                    anchors.top: parent.top
                    anchors.topMargin: Style.space(5)
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    text: todoRow.modelData.text
                    color: todoRow.modelData.done ? Qt.darker(root.contentForeground, 1.8) : root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    font.strikeout: todoRow.modelData.done
                  }

                  MouseArea {
                    id: todoMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: !editProcess.running
                    onClicked: root.toggleTodo(todoRow.modelData)
                  }
                }
              }

              TextField {
                id: addField
                width: parent.width
                visible: root.dayNote !== null && root.dayNote.date === root.selectedKey && root.dayNote.exists === true
                placeholderText: "Add a to-do"
                foreground: root.contentForeground
                font.family: root.contentFontFamily
                enabled: !editProcess.running
                onAccepted: {
                  root.addTodo(text)
                  text = ""
                }
                Keys.onEscapePressed: function(event) {
                  text = ""
                  keyCatcher.forceActiveFocus()
                  event.accepted = true
                }
              }

              PanelSectionHeader {
                visible: root.journalLines.length > 0 || noteField.visible
                topPadding: Style.space(6)
                text: "JOURNAL"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
              }

              // A preview, not the whole entry: the latest few lines, two
              // lines each, then a way into the note for the rest.
              Repeater {
                model: root.journalLines.slice(-root.journalPreviewCount)

                Item {
                  required property string modelData
                  width: dayColumn.width
                  height: journalText.implicitHeight

                  Text {
                    id: journalBullet
                    x: Style.space(6)
                    textFormat: Text.PlainText
                    text: "•"
                    color: Qt.darker(root.contentForeground, 1.4)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    id: journalText
                    anchors.left: journalBullet.right
                    anchors.leftMargin: Style.space(8)
                    anchors.right: parent.right
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: parent.modelData
                    color: Qt.darker(root.contentForeground, 1.15)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }
              }

              TextField {
                id: noteField
                width: parent.width
                visible: addField.visible
                placeholderText: "Add a note"
                foreground: root.contentForeground
                font.family: root.contentFontFamily
                enabled: !editProcess.running
                onAccepted: {
                  root.addNote(text)
                  text = ""
                }
                Keys.onEscapePressed: function(event) {
                  text = ""
                  keyCatcher.forceActiveFocus()
                  event.accepted = true
                }
              }

              Text {
                visible: root.journalLines.length > root.journalPreviewCount
                leftPadding: Style.space(6)
                textFormat: Text.PlainText
                text: "Read it all in Obsidian"
                color: moreMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Commons.Color.accent)
                  : Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.underline: moreMouse.containsMouse

                MouseArea {
                  id: moreMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openNote(root.selectedKey)
                }
              }

              Text {
                visible: root.journalError !== ""
                width: parent.width
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                text: root.journalError
                color: Commons.Color.urgent
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }

              // Room under the last box, like the month row had.
              Item {
                width: 1
                height: Style.space(4)
              }
            }
          }
        }
      }
    }
  }
}
