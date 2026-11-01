import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.snouhaud.rclone-mounter"
  ipcTarget: "io.github.snouhaud.rclone-mounter"
  manageIpc: false

  readonly property Item panelFlick: panel.loadedContent ? panel.loadedContent.panelFlick : null
  readonly property Item remoteColumn: panel.loadedContent ? panel.loadedContent.remoteColumn : null

  property bool cursorActive: false
  property int cursorPos: 0
  // Mode used for the next mount; starts at the configured default.
  property string mode: rclone.defaultMode
  // Two-step confirmation for forgetting the keyring password.
  property bool forgetArmed: false
  readonly property bool showForget: rclone.keyringStored && !rclone.blocked

  readonly property var modes: ["full", "writes", "read-only"]
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool showCount: setting("showCount", true) === true
  readonly property bool showMain: rclone.loaded && !rclone.blocked && !rclone.locked
  readonly property bool hasAlert: rclone.blocked || rclone.fuseMissing

  // Nerd Font (Material Design) glyphs.
  readonly property string glyphCloud: String.fromCodePoint(0xF0163)      // cloud-outline
  readonly property string glyphCloudOn: String.fromCodePoint(0xF0160)    // cloud-check
  readonly property string glyphFolder: String.fromCodePoint(0xF0770)     // folder-open
  readonly property string glyphLock: String.fromCodePoint(0xF033E)       // lock
  readonly property string glyphRefresh: String.fromCodePoint(0xF0450)    // refresh
  readonly property string glyphAlert: String.fromCodePoint(0xF002A)      // alert-outline
  readonly property string glyphDownload: String.fromCodePoint(0xF01DA)   // download
  readonly property string glyphCog: String.fromCodePoint(0xF0493)        // cog
  readonly property string glyphKeyOff: String.fromCodePoint(0xF0B76)     // key-remove

  // English by default; the Omarchy language, else the system locale, when a
  // catalog exists for it (see Strings.qml and Language.js).
  Strings { id: strings; directory: Qt.resolvedUrl("i18n") }

  // One alert per detected prerequisite problem. `action` is dispatched by
  // runAlertAction(); it never carries text from rclone.
  readonly property var alerts: {
    var list = []
    if (rclone.rcloneMissing)
      list.push({ code: "rcloneMissing", action: "installRclone", glyph: glyphDownload,
                  title: strings.t("alert.rcloneMissing"), help: strings.t("alert.rcloneMissingHelp"),
                  actionLabel: strings.t("alert.install") })
    if (rclone.fuseMissing)
      list.push({ code: "fuseMissing", action: "installFuse", glyph: glyphDownload,
                  title: strings.t("alert.fuseMissing"), help: strings.t("alert.fuseMissingHelp"),
                  actionLabel: strings.t("alert.install") })
    if (rclone.noConfig)
      list.push({ code: "noConfig", action: "configure", glyph: glyphCog,
                  title: strings.t("alert.noConfig"),
                  help: strings.t("alert.noConfigHelp").arg(rclone.configPath !== "" ? rclone.configPath : "~/.config/rclone/rclone.conf"),
                  actionLabel: strings.t("alert.configure") })
    if (rclone.issues.indexOf("badPassword") !== -1)
      list.push({ code: "badPassword", action: "unlock", glyph: glyphLock,
                  title: strings.t("alert.badPassword"), help: strings.t("alert.badPasswordHelp"),
                  actionLabel: strings.t("unlock.title") })
    if (rclone.issues.indexOf("secretToolMissing") !== -1)
      list.push({ code: "secretToolMissing", action: "installSecretTool", glyph: glyphDownload,
                  title: strings.t("alert.secretToolMissing"), help: strings.t("alert.secretToolMissingHelp"),
                  actionLabel: strings.t("alert.install") })
    if (rclone.issues.indexOf("zenityMissing") !== -1)
      list.push({ code: "zenityMissing", action: "installZenity", glyph: glyphDownload,
                  title: strings.t("alert.zenityMissing"), help: strings.t("alert.zenityMissingHelp"),
                  actionLabel: strings.t("alert.install") })
    if (rclone.issues.indexOf("noRemotes") !== -1)
      list.push({ code: "noRemotes", action: "configure", glyph: glyphCog,
                  title: strings.t("alert.noRemotes"), help: strings.t("alert.noRemotesHelp"),
                  actionLabel: strings.t("alert.configure") })
    return list
  }

  // Flat keyboard cursor: alerts, unlock, mode selector, then remotes.
  readonly property var cursorTargets: {
    var t = []
    for (var i = 0; i < alerts.length; i++) t.push({ section: "alert", index: i })
    if (rclone.locked && !rclone.blocked) t.push({ section: "unlock", index: 0 })
    if (showMain) {
      t.push({ section: "mode", index: 0 })
      for (var j = 0; j < rclone.remotes.length; j++) t.push({ section: "remotes", index: j })
    }
    if (showForget) t.push({ section: "forget", index: 0 })
    return t
  }
  readonly property var cursorTarget: cursorTargets.length > 0
    ? cursorTargets[Math.max(0, Math.min(cursorPos, cursorTargets.length - 1))] : null

  function cursorIs(section, index) {
    return cursorActive && cursorTarget !== null && cursorTarget.section === section && cursorTarget.index === index
  }

  function setCursor(section, index) {
    for (var i = 0; i < cursorTargets.length; i++) {
      if (cursorTargets[i].section === section && cursorTargets[i].index === index) {
        cursorActive = true
        cursorPos = i
        return
      }
    }
  }

  function defaultCursor() {
    // Land on the first remote when everything is fine, else on the first alert.
    if (alerts.length === 0) setCursor("remotes", 0)
    if (!cursorTarget || cursorTargets[cursorPos].section !== "remotes") cursorPos = 0
    cursorActive = true
  }

  function runAlertAction(action) {
    if (action === "installRclone") rclone.installRclone()
    else if (action === "installFuse") rclone.installFuse()
    else if (action === "configure") rclone.configureRclone()
    else if (action === "installSecretTool") rclone.installSecretTool()
    else if (action === "installZenity") rclone.installZenity()
    else if (action === "unlock") { rclone.unlock(); return }
    else return
    root.close()
  }

  function modeLabel(m) {
    if (m === "full") return strings.t("mode.full")
    if (m === "writes") return strings.t("mode.writes")
    if (m === "read-only") return strings.t("mode.readOnly")
    return "?"
  }

  function modeHelp(m) {
    if (m === "full") return strings.t("mode.fullHelp")
    if (m === "writes") return strings.t("mode.writesHelp")
    return strings.t("mode.readOnlyHelp")
  }

  function errorText() {
    var code = rclone.lastError
    if (code === "" || code === "cancelled") return ""
    var msg = strings.t("error." + code, strings.t("error.generic"))
    return rclone.lastErrorDetail !== "" ? msg + " — " + rclone.lastErrorDetail : msg
  }

  function heroMeta() {
    if (!rclone.loaded) return strings.t("hero.loading")
    if (rclone.blocked) return strings.t("hero.unavailable")
    if (rclone.locked) return strings.t("hero.locked")
    if (rclone.mountedCount > 0)
      return strings.tn("hero.mounted", rclone.mountedCount).arg(Commons.I18n.formatNumber(rclone.mountedCount))
    return strings.t("hero.none")
  }

  function remoteSubtitle(r) {
    if (rclone.busyRemote === r.name) return r.mounted ? strings.t("remote.unmounting") : strings.t("remote.mounting")
    if (r.mounted) return strings.t("remote.mountedAs").arg(r.mode !== "" ? modeLabel(r.mode) : "?")
    var parts = [r.type]
    if (r.forcedReadOnly) parts.push(strings.t("remote.forcedReadOnly"))
    return parts.join(" · ")
  }

  function selectedRemote() {
    if (!cursorTarget || cursorTarget.section !== "remotes") return null
    return rclone.remotes[cursorTarget.index] || null
  }

  function cycleMode(step) {
    var i = modes.indexOf(mode)
    mode = modes[(i + step + modes.length) % modes.length]
  }

  function moveCursor(dx, dy) {
    if (cursorTargets.length === 0) return
    if (dx !== 0 && cursorTarget && cursorTarget.section === "mode") { cycleMode(dx); return }
    if (dy === 0) return
    cursorPos = Math.max(0, Math.min(cursorTargets.length - 1, cursorPos + dy))
    scrollCursorIntoView()
  }

  function activateCursor() {
    var c = cursorTarget
    if (!c) return
    if (c.section === "alert") runAlertAction(alerts[c.index].action)
    else if (c.section === "unlock") rclone.unlock()
    else if (c.section === "mode") cycleMode(1)
    else if (c.section === "remotes") rclone.toggle(rclone.remotes[c.index], mode)
    else if (c.section === "forget") forgetPressed()
  }

  // First press arms, second press (within 4 s) deletes the password.
  function forgetPressed() {
    if (rclone.busy || !rclone.keyringStored) return
    if (!forgetArmed) { forgetArmed = true; forgetDisarm.restart(); return }
    forgetArmed = false
    forgetDisarm.stop()
    rclone.forgetPassword()
  }

  function scrollCursorIntoView() {
    if (!panelFlick) return
    var c = cursorTarget
    if (!c || c.section !== "remotes") {
      if (c && c.section !== "remotes") panelFlick.contentY = 0
      return
    }
    var item = remoteColumn ? remoteColumn.children[c.index] : null
    if (!item) return
    Qt.callLater(function() {
      var margin = Style.space(6)
      var top = item.mapToItem(panelFlick.contentItem, 0, 0).y
      var bottom = top + item.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < panelFlick.contentY + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > panelFlick.contentY + panelFlick.height - margin)
        panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    forgetArmed = false
    cursorActive = false
    cursorPos = 0
    if (panelFlick) panelFlick.contentY = 0
    rclone.refresh()
    Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus() })
  }
  onCursorTargetsChanged: if (cursorPos >= cursorTargets.length) cursorPos = Math.max(0, cursorTargets.length - 1)

  Service {
    id: rclone
    settings: root.settings
  }

  Timer {
    id: forgetDisarm
    interval: 4000
    onTriggered: root.forgetArmed = false
  }

  ShellIpc {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { rclone.refresh(); return "ok" }
    function mount(name: string, mode: string): string { rclone.mount(name, mode); return "ok" }
    function unmount(name: string): string { rclone.unmount(name); return "ok" }
    function forget(): string { rclone.forgetPassword(); return "ok" }
    function status(): string {
      var out = []
      for (var k = 0; k < rclone.issues.length; k++) out.push("issue\t" + rclone.issues[k])
      if (rclone.locked) out.push("locked")
      for (var i = 0; i < rclone.remotes.length; i++) {
        var r = rclone.remotes[i]
        out.push(r.name + "\t" + (r.mounted ? "mounted " + r.mode : "unmounted"))
      }
      return out.join("\n")
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: rclone.mountedCount > 0 ? root.glyphCloudOn : root.glyphCloud
    labelText: root.hasAlert ? "!"
      : rclone.locked ? ""
      : root.showCount && rclone.mountedCount > 0 ? Commons.I18n.formatNumber(rclone.mountedCount) : ""
    foreground: root.hasAlert ? (root.bar ? root.bar.urgent : Commons.Color.urgent)
      : rclone.mountedCount > 0 ? root.barForeground : Qt.darker(root.barForeground, 1.55)
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) rclone.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(600))

    content: PanelKeyCatcher {
      id: keyCatcher
      property alias panelFlick: panelFlick
      property alias remoteColumn: remoteColumn
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.defaultCursor(); return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") rclone.refresh()
        else if (t === "m" || t === "M") root.cycleMode(1)
        else if (t === "o" || t === "O") rclone.openFolder(root.selectedRemote())
        else if (t === "u" || t === "U") { if (rclone.locked) rclone.unlock() }
        else if (t === "f" || t === "F") { if (root.showForget) { root.setCursor("forget", 0); root.forgetPressed() } }
        else if (t === "c" || t === "C") { if (rclone.noConfig || rclone.issues.indexOf("noRemotes") !== -1) root.runAlertAction("configure") }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: strings.t("title")
            meta: root.heroMeta()
            detail: root.showMain ? rclone.base : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: rclone.mountedCount > 0 ? 1.0 : 0.6
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: rclone.mountedCount > 0 ? root.glyphCloudOn : root.glyphCloud
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
            trailingControl: Component {
              PanelActionButton {
                iconText: root.glyphRefresh
                tooltipText: strings.t("refresh")
                foreground: hero.foreground
                fontFamily: hero.fontFamily
                enabled: !rclone.refreshing
                onClicked: rclone.refresh()
              }
            }
          }

          Column {
            visible: root.alerts.length > 0
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.alerts
              AlertRow {
                required property var modelData
                required property int index
                width: parent.width
                alert: modelData
                rowIndex: index
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            text: root.errorText()
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          UnlockRow {
            visible: rclone.locked && !rclone.blocked
            width: parent.width
          }

          Column {
            visible: root.showMain
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: strings.t("mode.header")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            ButtonGroup {
              options: root.modes.map(function(m) { return { value: m, label: root.modeLabel(m) } })
              value: root.mode
              foreground: root.foreground
              fontFamily: root.fontFamily
              focusable: false
              cursorIndex: root.cursorIs("mode", 0) ? root.modes.indexOf(root.mode) : -1
              onChanged: function(v) { root.mode = v }
              onHovered: function(index, on) { if (on) root.setCursor("mode", 0) }
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: root.modeHelp(root.mode)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          PanelSeparator {
            visible: root.showMain
            foreground: root.foreground
          }

          Column {
            visible: root.showMain && rclone.issues.indexOf("noRemotes") === -1
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: strings.t("remotes.header")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: rclone.remotes.length === 0
              width: parent.width
              text: strings.t("remotes.empty")
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            Column {
              id: remoteColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: rclone.remotes
                RemoteRow {
                  required property var modelData
                  required property int index
                  width: remoteColumn.width
                  remote: modelData
                  rowIndex: index
                }
              }
            }
          }

          PanelSeparator {
            visible: root.showForget
            foreground: root.foreground
          }

          ForgetRow {
            visible: root.showForget
            width: parent.width
          }
        }
      }
    }
  }

  component AlertRow: CursorSurface {
    id: alertRow
    property var alert: null
    property int rowIndex: 0

    hasCursor: root.cursorIs("alert", rowIndex)
    foreground: root.urgent
    bordered: true
    implicitHeight: alertLayout.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCursor("alert", alertRow.rowIndex)
      onClicked: root.runAlertAction(alertRow.alert.action)
    }

    RowLayout {
      id: alertLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(4)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: root.glyphAlert
        color: root.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)
        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: alertRow.alert ? alertRow.alert.title : ""
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }
        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: alertRow.alert ? alertRow.alert.help : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }

      PanelActionButton {
        iconText: alertRow.alert ? alertRow.alert.glyph : ""
        tooltipText: alertRow.alert ? alertRow.alert.actionLabel : ""
        foreground: root.foreground
        fontFamily: root.fontFamily
        hasCursor: alertRow.hasCursor
        Layout.alignment: Qt.AlignVCenter
        onHovered: function(on) { if (on) root.setCursor("alert", alertRow.rowIndex) }
        onClicked: root.runAlertAction(alertRow.alert.action)
      }
    }
  }

  component ForgetRow: CursorSurface {
    id: forgetRow
    hasCursor: root.cursorIs("forget", 0)
    foreground: root.forgetArmed ? root.urgent : root.foreground
    implicitHeight: forgetLayout.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      enabled: !rclone.busy
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCursor("forget", 0)
      onClicked: root.forgetPressed()
    }

    RowLayout {
      id: forgetLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(4)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: root.glyphKeyOff
        color: root.forgetArmed ? root.urgent : root.foreground
        opacity: root.forgetArmed ? 1.0 : 0.7
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)
        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: rclone.busyRemote === "*forget*" ? strings.t("forget.working")
            : root.forgetArmed ? strings.t("forget.confirm") : strings.t("forget.title")
          color: root.forgetArmed ? root.urgent : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: strings.t("forget.help")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }

  component UnlockRow: CursorSurface {
    hasCursor: root.cursorIs("unlock", 0)
    foreground: root.foreground
    implicitHeight: unlockLayout.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      enabled: !rclone.busy
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCursor("unlock", 0)
      onClicked: rclone.unlock()
    }

    RowLayout {
      id: unlockLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: root.glyphLock
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)
        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: strings.t("unlock.title")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: strings.t("unlock.help")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }

  component RemoteRow: CursorSurface {
    id: row
    property var remote: null
    property int rowIndex: 0
    readonly property bool rowBusy: rclone.busyRemote === (remote ? remote.name : "")

    hasCursor: root.cursorIs("remotes", rowIndex)
    foreground: root.foreground
    implicitHeight: rowLayout.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCursor("remotes", row.rowIndex)
      onClicked: if (row.remote && row.remote.mounted) rclone.openFolder(row.remote)
    }

    RowLayout {
      id: rowLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(4)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: row.remote && row.remote.mounted ? root.glyphCloudOn : root.glyphCloud
        color: root.foreground
        opacity: row.remote && row.remote.mounted ? 1.0 : 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)
        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: row.remote ? row.remote.name : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: row.remote ? root.remoteSubtitle(row.remote) : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        visible: row.remote && row.remote.mounted
        iconText: root.glyphFolder
        tooltipText: strings.t("remote.open")
        foreground: root.foreground
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onHovered: function(on) { if (on) root.setCursor("remotes", row.rowIndex) }
        onClicked: rclone.openFolder(row.remote)
      }

      ToggleSwitch {
        id: mountSwitch
        checked: row.remote ? row.remote.mounted : false
        busy: row.rowBusy
        interactive: rclone.canMount && (!rclone.busy || row.rowBusy)
        opacity: rclone.canMount ? 1.0 : 0.4
        cursorRing: false
        foreground: root.foreground
        Layout.alignment: Qt.AlignVCenter
        onHovered: function(on) { if (on) root.setCursor("remotes", row.rowIndex) }
        onToggled: rclone.toggle(row.remote, root.mode)

        PanelToolTip {
          visible: mountSwitch.containsMouse
          text: !rclone.canMount ? strings.t("alert.fuseMissing")
            : row.remote && row.remote.mounted ? strings.t("remote.unmount")
            : strings.t("remote.mountWith").arg(root.modeLabel(row.remote && row.remote.forcedReadOnly ? "read-only" : root.mode))
          fontFamily: root.fontFamily
        }
      }
    }
  }
}
