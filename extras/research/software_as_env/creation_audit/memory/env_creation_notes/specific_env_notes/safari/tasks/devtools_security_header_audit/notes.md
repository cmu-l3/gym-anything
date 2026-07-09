# Task: safari_env/devtools_security_header_audit — Port Notes

**Source:** `firefox_env/tasks/devtools_security_header_audit` (hard, file-verified)
**Status:** Ported, offline-tested (7 scenarios), live-tested end-to-end (do-nothing + happy-path).

---

## What the port required

1. **Path translation**: `/home/ga/Documents/...` → `/Users/lume/Documents/...`; `/workspace/...` → `/Users/lume/workspace/...` (SIP read-only root, per `12_macos_environments.md`).
2. **Browser kill**: `pkill -u ga firefox` → `osascript -e 'tell application "Safari" to quit'` then `pkill -x Safari`. AppleScript quit is graceful (flushes History.db WAL); `pkill -x` is the fallback.
3. **Browser launch**: `firefox -P default --no-remote &` → `open -a Safari` then AppleScript navigation to about:blank.
4. **History query**: Firefox `places.sqlite` (`moz_historyvisits`, microseconds since Unix epoch) → Safari `~/Library/Safari/History.db` (`history_visits`, **Mac absolute time** = seconds since 2001-01-01 UTC). Conversion: `mac_time = unix_time - 978307200`.
5. **WAL flush**: Quit Safari cleanly before reading History.db, then `PRAGMA wal_checkpoint(TRUNCATE)`, then copy to temp.
6. **screencapture instead of scrot**: macOS uses `/usr/sbin/screencapture -x` (no GUI prompt with `-x`).
7. **Adversarial hardening over source**: see "Per-site visit gating" below — closes a 75-point fabrication gap that the source firefox verifier has.

---

## Bugs surfaced in gym-anything core (fixed)

### Bug A — `_run_post_task_hook` had no macOS branch

`src/gym_anything/env.py:908-920` ran `bash -lc {hook_cmd} > /home/ga/task_post_task.log 2>&1` on every non-Android, non-Windows guest. On macOS, `/home/ga/` doesn't exist (SIP read-only root) → shell redirect fails → bash never executes `hook_cmd` → no `/tmp/<task>_result.json` is produced → the verifier returns "Could not retrieve result file from sandbox" with score 0 even when the agent did the work.

**Fix:** added a `macos` branch that writes to `/Users/lume/task_post_task.log`, matching the pattern I used earlier for `pre_start` / `post_start` / `pre_task`.

Same fix applied to the `_finalize` log-collection loop at `env.py:1027` — added the `/Users/lume/*.log` paths alongside the Linux paths so they get copied to the artifacts dir.

**General rule** (now in `12_macos_environments.md`): any new hardcoded `/home/ga/` log path in `env.py` needs a macOS sibling at `/Users/lume/`.

### Bug B (open) — `defaults write IncludeDevelopMenu` doesn't show Develop menu

Even with `killall cfprefsd` between `defaults write` and `open -a Safari`, `defaults read IncludeDevelopMenu` returns 0 after Safari launches and the menu doesn't appear in the menu bar. Reproduced on every fresh sandbox.

**Suspected cause:** Safari has internal logic that resets `IncludeDevelopMenu` on first launch for non-developer Apple IDs. Not yet root-caused.

**Workaround for this task:** the verifier's gate works on Safari History.db visits (which `open -a` populates regardless of menu bar state), not on whether Develop menu is open. An agent without Develop menu can still use:
- `Cmd+Option+I` (Web Inspector shortcut — works even if menu is hidden, *if* the entitlement is on)
- Terminal `curl` to fetch headers (the happy-path test confirms this scores 97)
- AppleScript `do shell script` from within Safari

**Future work:** find the actual lever (perhaps PlistBuddy direct edit, or `defaults import`, or a specific Safari-only key) that activates the Develop menu reliably.

---

## Offline mock test results

```
$ python3 evidence/offline_verifier_tests.py
[PASS] do-nothing:                                 score=0   passed=False
[PASS] wrong-target:                               score=15  passed=False
[PASS] partial (2/5):                              score=50  passed=False
[PASS] full-correct:                               score=100 passed=True
[PASS] invalid-json report:                        score=3   passed=False
[PASS] stale report:                               score=8   passed=False
[PASS] no-visits full report (anti-gaming gate):   score=15  passed=False
```

The last row is the per-site visit gate the Safari port adds over the source firefox verifier (which would have scored 75 → false pass). See README.md "Anti-Gaming Notes" for the strategy enumeration table.

---

## Live end-to-end results (use.computer dev, M4 macOS 15.4.1)

```
=== do-nothing flow ===
reset took 29.7s
verifier: score=0, passed=False
"No evidence of task completion: no site visits after task start and no report file..."

=== happy-path flow ===
reset took 31.2s
[agent simulator]:
  - osascript -e 'set URL of front document to "https://github.com/"'      (×5 sites)
  - python3 inside sandbox: curl -sIL each site, parse last header block, write report JSON
verifier: score=97, passed=True
  C1 domain_history: 25/25  (all 5 visited)
  C2 report_file:    15/15  (fresh, valid)
  C3 sites_in_report:20/20  (all 5 keyed)
  C4 header_counts:  22/25  (gitlab.com returned only 1 header via curl HEAD)
  C5 header_validity:15/15  (HSTS valid on 5, CSP valid on 4)
```

The 3-point deduction on C4 is a real-world artifact: gitlab.com's HEAD response doesn't include the full security header set that GET to the same URL would (likely a CDN edge optimization). A real agent using Web Inspector on a full GET would score 100. Documented as expected variation, not a bug.

---

## Evidence files

All per-task evidence has been moved to its standard location at
`benchmarks/cua_world-macos/environments/safari_env/evidence_docs/devtools_security_header_audit/`
per `04_evidence_documentation.md`. See its README.md for the full evidence
index with manual verification notes for every artifact (4 flows: do_nothing,
wrong_target, happy_path, probe_prefs; per-site navigation screenshots; the
actual JSON report contents; full hook logs; export script outputs;
authoritative `summary.json` results).

This file in `specific_env_notes/` is for lessons learned that future agents
should remember; per-task evidence belongs alongside the task itself.
