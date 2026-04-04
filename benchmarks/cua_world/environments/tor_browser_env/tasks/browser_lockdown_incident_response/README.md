# Task: browser_lockdown_incident_response

## Domain Context

Digital forensics analysts and incident responders at human rights organizations sometimes need to perform an emergency browser lockdown procedure when a field operative's device may have been compromised. Before handing the device to a forensics team, the analyst must: harden the browser security, capture evidence of the current state, document the current exit node, configure the browser to clear sensitive data, prevent future session persistence, and create a formal incident report. This is a multi-step procedure that combines both browser configuration and file system operations.

## Goal

Perform a 6-step emergency browser lockdown procedure:

1. **Security hardening**: Change Security Level to **Safest**
2. **Evidence capture**: Save a screenshot to `/home/ga/Desktop/incident_screenshot.png`
3. **History export**: Visit `https://check.torproject.org/` to document exit node, then set `privacy.clearOnShutdown.history` = `true` in `about:config`
4. **Data clearing**: Clear ALL browsing data (history, downloads, cookies, cache, offline data) with time range "Everything"
5. **Configuration lock**: Set `browser.privatebrowsing.autostart` = `true` in `about:config`
6. **Incident report**: Write `/home/ga/Desktop/incident_report.txt` containing at minimum "LOCKDOWN COMPLETE" and the current date

## Difficulty

**very_hard** — Requires 6 independent operations combining browser UI actions, `about:config` modifications (2 different preferences), file system operations (screenshot + text file), browsing to a specific URL, and data clearing. The combination of all 6 steps distinguishes this from simpler tasks.

## Success Criteria

- **Pass threshold**: 60+ points AND Security Level = Safest (required gate)
- Full score: 100 points across 9 criteria

## Scoring Breakdown

| Criterion | Points | Required |
|-----------|--------|----------|
| Security level = Safest (slider=4) | 20 | Yes (gate) |
| incident_screenshot.png on Desktop (>1KB) | 15 | No |
| Screenshot is newly created | 5 | No |
| check.torproject.org in history (or history cleared) | 10 | No |
| privacy.clearOnShutdown.history = true | 10 | No |
| Browser history cleared (<5 visits) | 10 | No |
| browser.privatebrowsing.autostart = true | 15 | No |
| incident_report.txt on Desktop | 10 | No |
| Report is new and contains "LOCKDOWN" | 5 | No |

## Verification Strategy

**Primary (prefs.js)**: Read `prefs.js` from the Tor Browser profile for security level, `privacy.clearOnShutdown.history`, and `browser.privatebrowsing.autostart`.

**Secondary (history count)**: Query `places.sqlite` for total visit count — after clearing, should be <5.

**Tertiary (files)**: Check Desktop for `incident_screenshot.png` and `incident_report.txt` with timestamps after task start and correct content.

## Starting State

Tor Browser is launched and connected. Security level is at default "Standard". No screenshot or report files exist on the Desktop (setup removes any stale copies). The target `about:config` preferences are at their defaults.

## Edge Cases

- Screenshot can be taken using: PrintScreen key, GNOME screenshot tool (Super+Shift+Print), scrot in terminal, or via the browser's screenshot functionality
- `scrot /home/ga/Desktop/incident_screenshot.png` from a terminal is the most reliable method
- "Clear Data" is in Settings → Privacy & Security → Cookies and Site Data → Clear Data, OR via the History menu → Clear Recent History with "Everything" selected
- The data clearing dialog must have "Everything" selected for the time range (not just "1 hour" or "Today")
- After data clearing, the history visit count may be 0 — the verifier detects this as evidence of clearing
- For the incident report: any text file creation method works (gedit, nano, echo, terminal redirect)
- The report must contain the word "LOCKDOWN" (case-insensitive matching in the verifier)
- Setting `browser.privatebrowsing.autostart = true` will affect subsequent browser sessions (forces permanent private browsing)
- Note: clearing history first, then checking check.torproject.org — the verifier handles this edge case by awarding partial credit if history is cleared and check.torproject.org visit is unconfirmable
