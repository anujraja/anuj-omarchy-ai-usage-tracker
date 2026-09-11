# Anuj Omarchy AI Usage Tracker

An Omarchy bar plugin that shows how much of each AI plan is remaining. It uses
the same themed agents glyph as the built-in Omarchy Agents widget, with tabs
for Claude, Codex, and Grok.

Works on any Omarchy machine. There are no hardcoded home directories or
host-specific collector paths.

## What it shows

Each tab leads with **percent remaining**, the plan name, and when the window
resets. Open the panel for meters, pace, a seven-day token chart, and
API-equivalent estimates.

```text
Claude · 82%   Codex · 98%   Grok · 99%
```

A provider turns red when usage exceeds the prorated portion of its seven-day
window.

- Left-click the bar icon to open or close details.
- Right-click or middle-click to refresh.
- Press `R` while the panel is open to refresh.
- Press Escape to close.

## Requirements

- Omarchy with Quickshell plugins. Claude and Codex use the collectors Omarchy
  already ships (`omarchy-agent-usage-claude` and `omarchy-agent-usage-codex`
  on `PATH`).
- Claude Code signed in (`claude auth login`) for Claude remaining.
- Codex CLI signed in (`codex login`) for Codex remaining.
- Grok CLI signed in (`grok login`) for Grok remaining. The plugin reads the
  same `~/.grok/auth.json` the CLI uses and refreshes the token when needed.

The plugin does not read or store provider passwords. It uses credentials the
CLIs already manage.

## Installation

```bash
omarchy plugin add https://github.com/anujraja/anuj-omarchy-ai-usage-tracker.git --enable
```

Then hide the stock Agents widget if both icons appear:

```bash
omarchy plugin disable omarchy.agents
```

The plugin refreshes every five minutes by default:

```bash
omarchy bar set anuj-omarchy-ai-usage-tracker refreshIntervalSec 600 --json
```

## Removal

```bash
omarchy plugin remove anuj-omarchy-ai-usage-tracker
omarchy plugin enable omarchy.agents
```

## License

MIT
