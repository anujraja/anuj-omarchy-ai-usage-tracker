import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property var claude: ({ id: "claude", name: "Claude", weekly: null, limits: [], recentDays: [], status: "Loading…" })
  property var codex: ({ id: "codex", name: "Codex", weekly: null, limits: [], recentDays: [], status: "Loading…" })
  property bool refreshing: false
  property string lastError: ""
  property date lastUpdated: new Date(0)
  property int _pending: 0
  property string _claudeOutput: ""
  property string _claudeError: ""
  property string _codexOutput: ""
  property string _codexError: ""

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 300, 60, 3600)

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, minimum, maximum) {
    var value = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  function conciseError(value, fallback) {
    var text = String(value || fallback || "Usage request failed").replace(/\s+/g, " ").trim()
    return text.length > 180 ? text.substring(0, 177) + "…" : text
  }

  function refresh() {
    if (refreshing || claudeProcess.running || codexProcess.running) return
    refreshing = true
    lastError = ""
    _pending = 2
    _claudeOutput = ""
    _claudeError = ""
    _codexOutput = ""
    _codexError = ""
    claudeProcess.command = ["omarchy-agent-usage-claude", "--limits-only"]
    codexProcess.command = ["omarchy-agent-usage-codex", "--limits-only"]
    claudeProcess.running = true
    codexProcess.running = true
  }

  function finishOne() {
    _pending = Math.max(0, _pending - 1)
    if (_pending === 0) {
      refreshing = false
      lastUpdated = new Date()
    }
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
      if (exitCode !== 0) {
        root.claude = Object.assign({}, root.claude, { status: root.conciseError(stderr || stdout, "Could not load Claude usage") })
        root.lastError = root.claude.status
      } else {
        var parsed = Model.parseProvider(stdout, "claude", Date.now())
        if (parsed.ok) root.claude = parsed.provider
        else {
          root.claude = Object.assign({}, root.claude, { status: parsed.error })
          root.lastError = parsed.error
        }
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
      if (exitCode !== 0) {
        root.codex = Object.assign({}, root.codex, { status: root.conciseError(stderr || stdout, "Could not load Codex usage") })
        root.lastError = root.codex.status
      } else {
        var parsed = Model.parseProvider(stdout, "codex", Date.now())
        if (parsed.ok) root.codex = parsed.provider
        else {
          root.codex = Object.assign({}, root.codex, { status: parsed.error })
          root.lastError = parsed.error
        }
      }
      root.finishOne()
    }
  }
}
