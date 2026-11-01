import QtQuick
import Quickshell
import Quickshell.Io

// Talks to rclone-mounts.sh. Every call passes argv directly (no shell string)
// and every reply is one JSON line, validated and bounded before use.
Item {
  id: root

  property var settings: ({})

  property bool loaded: false
  property bool locked: false
  property string base: ""
  property var remotes: []
  // Prerequisite problems from the last status: rcloneMissing, fuseMissing,
  // noConfig, noRemotes.
  property var issues: []
  property string configPath: ""
  property string lastError: ""
  property string lastErrorDetail: ""
  // Remote currently being mounted/unmounted ("" when idle), or "*unlock*".
  property string busyRemote: ""

  readonly property bool busy: actionProcess.running
  readonly property bool refreshing: statusProcess.running
  readonly property bool rcloneMissing: issues.indexOf("rcloneMissing") !== -1
  readonly property bool fuseMissing: issues.indexOf("fuseMissing") !== -1
  readonly property bool noConfig: issues.indexOf("noConfig") !== -1
  // Problems that prevent listing remotes at all.
  readonly property bool blocked: rcloneMissing || noConfig
  readonly property bool canMount: !blocked && !fuseMissing && !locked
  readonly property var knownIssues: ["rcloneMissing", "fuseMissing", "noConfig", "noRemotes"]
  readonly property int mountedCount: {
    var n = 0
    for (var i = 0; i < remotes.length; i++) if (remotes[i].mounted) n++
    return n
  }

  readonly property string helperPath: decodeURIComponent(String(Qt.resolvedUrl("rclone-mounts.sh")).replace(/^file:\/\//, ""))
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 3600)
  readonly property string mountBase: String(setting("mountBase", "~/mnt")).substring(0, 512)
  readonly property string excludedRemotes: String(setting("excludedRemotes", "bdvideos-local")).substring(0, 1024)
  readonly property string readOnlyRemotes: String(setting("readOnlyRemotes", "")).substring(0, 1024)
  readonly property bool openAfterMount: setting("openAfterMount", true) === true
  readonly property string defaultMode: validMode(setting("defaultMode", "full")) ? String(setting("defaultMode", "full")) : "full"

  signal actionFinished(bool ok, string action, string name)

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    return Math.max(min, Math.min(max, n))
  }

  function validMode(mode) {
    return mode === "full" || mode === "writes" || mode === "read-only"
  }

  function validName(name) {
    return /^[A-Za-z0-9_][A-Za-z0-9_.@+-]{0,63}$/.test(String(name || ""))
  }

  function parse(raw) {
    try {
      var text = String(raw || "").trim()
      if (text.length === 0 || text.length > 200000) return null
      var obj = JSON.parse(text.split("\n").pop())
      return obj && typeof obj === "object" ? obj : null
    } catch (e) {
      return null
    }
  }

  function setError(code, detail) {
    lastError = String(code || "")
    lastErrorDetail = String(detail || "").replace(/\s+/g, " ").trim().substring(0, 200)
  }

  function clearError() {
    lastError = ""
    lastErrorDetail = ""
  }

  function refresh() {
    if (statusProcess.running) return
    statusProcess.command = ["bash", helperPath, "status", mountBase, excludedRemotes, readOnlyRemotes]
    statusProcess.running = true
  }

  function applyStatus(raw) {
    var obj = parse(raw)
    if (!obj) { setError("parseFailed", ""); return }
    if (obj.ok !== true) { setError(obj.error, obj.detail); loaded = true; return }
    locked = obj.locked === true
    base = String(obj.base || "").substring(0, 512)
    configPath = String(obj.configPath || "").substring(0, 512)
    var found = []
    var raw = Array.isArray(obj.issues) ? obj.issues.slice(0, 8) : []
    for (var k = 0; k < raw.length; k++) {
      var code = String(raw[k])
      if (knownIssues.indexOf(code) !== -1 && found.indexOf(code) === -1) found.push(code)
    }
    issues = found
    var list = Array.isArray(obj.remotes) ? obj.remotes.slice(0, 100) : []
    var clean = []
    for (var i = 0; i < list.length; i++) {
      var r = list[i]
      if (!r || !validName(r.name)) continue
      var mode = String(r.mode || "")
      clean.push({
        name: String(r.name),
        type: String(r.type || "").substring(0, 32),
        path: String(r.path || "").substring(0, 600),
        mounted: r.mounted === true,
        mode: validMode(mode) ? mode : "",
        forcedReadOnly: r.forcedReadOnly === true
      })
    }
    remotes = clean
    loaded = true
    // Prerequisite errors are shown as alerts from `issues`; drop stale ones.
    if (["parseFailed", "badPassword", "rcloneMissing", "fuseMissing", "noConfig", "statusFailed"].indexOf(lastError) !== -1) clearError()
  }

  // Fixed commands only: nothing from rclone output is ever interpolated here.
  function runInTerminal(command) {
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", command])
  }

  function installRclone() { runInTerminal("omarchy pkg add rclone") }
  function installFuse() { runInTerminal("omarchy pkg add fuse3") }
  function configureRclone() { runInTerminal("rclone config") }

  function runAction(command, name) {
    if (actionProcess.running) return
    clearError()
    busyRemote = name
    actionProcess.actionName = command[2]
    actionProcess.command = command
    actionProcess.running = true
  }

  function mount(name, mode) {
    if (!validName(name)) return
    if (!validMode(mode)) mode = defaultMode
    runAction(["bash", helperPath, "mount", mountBase, name, mode, readOnlyRemotes, openAfterMount ? "1" : "0"], name)
  }

  function unmount(name) {
    if (!validName(name)) return
    runAction(["bash", helperPath, "unmount", mountBase, name], name)
  }

  function toggle(remote, mode) {
    if (!remote || busy) return
    if (fuseMissing) { setError("fuseMissing", ""); return }
    if (remote.mounted) unmount(remote.name)
    else mount(remote.name, mode)
  }

  function unlock() {
    runAction(["bash", helperPath, "unlock"], "*unlock*")
  }

  function openFolder(remote) {
    if (!remote || !remote.mounted || !remote.path) return
    Quickshell.execDetached(["xdg-open", remote.path])
  }

  onSettingsChanged: Qt.callLater(refresh)

  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.applyStatus(statusOut.text)
      else root.setError("statusFailed", "")
    }
  }

  Process {
    id: actionProcess
    property string actionName: ""
    running: false
    command: []
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    onExited: function(exitCode) {
      var obj = root.parse(actionOut.text)
      var name = root.busyRemote
      var ok = obj !== null && obj.ok === true
      if (!ok) root.setError(obj ? obj.error : "commandFailed", obj ? obj.detail : "")
      root.busyRemote = ""
      root.actionFinished(ok, actionProcess.actionName, name)
      root.refresh()
    }
  }
}
