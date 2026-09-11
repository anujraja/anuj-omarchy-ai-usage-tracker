import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property var claude: emptyProvider("claude", "Claude")
  property var codex: emptyProvider("codex", "Codex")
  property var grok: emptyProvider("grok", "Grok")
  property bool refreshing: false
  property string lastError: ""
  property date lastUpdated: new Date(0)
  property int _pending: 0
  property string _claudeOutput: ""
  property string _claudeError: ""
  property string _codexOutput: ""
  property string _codexError: ""
  property string _grokOutput: ""
  property string _grokError: ""

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 300, 60, 3600)
  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string usageDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/agents/usage"
  readonly property string grokCollector: localPath("collect-grok")

  function emptyProvider(id, name) {
    return { id: id, name: name, weekly: null, limits: [], modelUsage: {}, recentDays: [], status: "Loading…" }
  }

  function localPath(name) {
    var url = String(Qt.resolvedUrl(name) || "")
    if (url.indexOf("file://") === 0) url = url.slice(7)
    return url
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, minimum, maximum) {
    var value = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  function setProvider(kind, value) {
    if (kind === "codex") root.codex = value
    else if (kind === "grok") root.grok = value
    else root.claude = value
  }

  function providerFor(kind) {
    if (kind === "codex") return root.codex
    if (kind === "grok") return root.grok
    return root.claude
  }

  function applyRecord(kind, content, fallbackStatus) {
    var parsed = Model.parseProvider(String(content || ""), kind, Date.now())
    if (!parsed.ok) {
      if (fallbackStatus) root.setProvider(kind, Object.assign({}, root.providerFor(kind), { status: fallbackStatus }))
      return false
    }
    root.setProvider(kind, parsed.provider)
    return true
  }

  function conciseError(value, fallback) {
    var text = String(value || fallback || "Usage request failed").replace(/\s+/g, " ").trim()
    return text.length > 180 ? text.substring(0, 177) + "…" : text
  }

  function finishOne() {
    _pending = Math.max(0, _pending - 1)
    if (_pending === 0) {
      refreshing = false
      lastUpdated = new Date()
    }
  }

  function refresh() {
    if (claudeProcess.running || codexProcess.running || grokProcess.running) return
    refreshing = true
    lastError = ""
    _pending = 3
    _claudeOutput = ""
    _claudeError = ""
    _codexOutput = ""
    _codexError = ""
    _grokOutput = ""
    _grokError = ""
    claudeProcess.command = ["omarchy-agent-usage-claude", "--limits-only"]
    codexProcess.command = ["omarchy-agent-usage-codex", "--limits-only"]
    grokProcess.command = ["python3", root.grokCollector, "--limits-only"]
    claudeProcess.running = true
    codexProcess.running = true
    grokProcess.running = true
  }

  FileView {
    path: root.usageDir + "/claude.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyRecord("claude", text())
    onFileChanged: reload()
    onLoadFailed: if (!root.claude.weekly) root.claude = Object.assign({}, root.claude, { status: "Waiting for Claude usage" })
  }

  FileView {
    path: root.usageDir + "/codex.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyRecord("codex", text())
    onFileChanged: reload()
    onLoadFailed: if (!root.codex.weekly) root.codex = Object.assign({}, root.codex, { status: "Waiting for Codex usage" })
  }

  FileView {
    path: root.usageDir + "/grok.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyRecord("grok", text())
    onFileChanged: reload()
    onLoadFailed: if (!root.grok.weekly) root.grok = Object.assign({}, root.grok, { status: "Waiting for Grok usage" })
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: claudeProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: claudeStdout
      waitForEnd: true
      onStreamFinished: root._claudeOutput = text
    }
    stderr: StdioCollector {
      id: claudeStderr
      waitForEnd: true
      onStreamFinished: root._claudeError = text
    }
    onExited: function(exitCode) {
      var stdout = String(claudeStdout.text || root._claudeOutput || "")
      var stderr = String(claudeStderr.text || root._claudeError || "")
      if (exitCode !== 0 && !root.applyRecord("claude", stdout)) {
        root.claude = Object.assign({}, root.claude, { status: root.conciseError(stderr || stdout, "Could not load Claude usage") })
        if (!root.claude.weekly) root.lastError = root.claude.status
      } else if (stdout !== "") {
        root.applyRecord("claude", stdout, root.conciseError(stderr, "Could not parse Claude usage"))
      }
      root.finishOne()
    }
  }

  Process {
    id: codexProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: codexStdout
      waitForEnd: true
      onStreamFinished: root._codexOutput = text
    }
    stderr: StdioCollector {
      id: codexStderr
      waitForEnd: true
      onStreamFinished: root._codexError = text
    }
    onExited: function(exitCode) {
      var stdout = String(codexStdout.text || root._codexOutput || "")
      var stderr = String(codexStderr.text || root._codexError || "")
      if (exitCode !== 0 && !root.applyRecord("codex", stdout)) {
        root.codex = Object.assign({}, root.codex, { status: root.conciseError(stderr || stdout, "Could not load Codex usage") })
        if (!root.codex.weekly) root.lastError = root.codex.status
      } else if (stdout !== "") {
        root.applyRecord("codex", stdout, root.conciseError(stderr, "Could not parse Codex usage"))
      }
      root.finishOne()
    }
  }

  Process {
    id: grokProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: grokStdout
      waitForEnd: true
      onStreamFinished: root._grokOutput = text
    }
    stderr: StdioCollector {
      id: grokStderr
      waitForEnd: true
      onStreamFinished: root._grokError = text
    }
    onExited: function(exitCode) {
      var stdout = String(grokStdout.text || root._grokOutput || "")
      var stderr = String(grokStderr.text || root._grokError || "")
      if (!root.applyRecord("grok", stdout)) {
        root.grok = Object.assign({}, root.grok, { status: root.conciseError(stderr || stdout, "Could not load Grok usage") })
        if (!root.grok.weekly) root.lastError = root.grok.status
      }
      root.finishOne()
    }
  }
}
