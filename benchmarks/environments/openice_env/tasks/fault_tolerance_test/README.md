# fault_tolerance_test

**Task ID:** fault_tolerance_test@1
**Difficulty:** very_hard
**Domain:** Biomedical Engineering / Equipment Validation
**Environment:** openice_env@0.1

---

## Clinical Context

Pre-deployment fault tolerance testing for an ICU monitoring system. Hospital administration requires documented evidence that the OpenICE-based monitoring infrastructure can maintain patient safety when a device adapter unexpectedly fails. A biomedical engineer must execute a structured validation procedure and produce a written report suitable for clinical governance review.

---

## Goal

Execute a complete device fault tolerance validation test in OpenICE. Specifically:

1. **Create two identical Multiparameter Monitor adapters** to simulate a redundant dual-monitor setup.
2. **Launch the Vital Signs clinical application** and confirm both devices are visible and streaming data simultaneously.
3. **Simulate a device adapter failure** by stopping or closing one of the running device adapter instances. The agent must discover on its own what method is available in the OpenICE interface to stop a device (e.g., closing its window, using a stop button, or terminating its process).
4. **Observe the system response**: Does OpenICE detect the lost device? Does monitoring continue on the remaining device? Are there visual failure indicators?
5. **Restore full monitoring redundancy** by creating a replacement device adapter.
6. **Write a fault tolerance validation report** to `/home/ga/Desktop/fault_tolerance_report.txt` documenting the complete test procedure, observed system behavior at each stage, and an assessment of OpenICE's fault tolerance characteristics and suitability for safety-critical ICU deployment.

OpenICE Supervisor is already running on the desktop at task start.

---

## Key Challenge

This is a **very hard** task. The task description gives only the high-level goal — it does not specify which buttons to press, how to navigate menus, or what exact mechanism exists to stop a device adapter. The agent must:

- Explore the OpenICE interface to understand how device adapters are managed.
- Figure out how to stop/close a running device adapter (e.g., closing its application window, clicking a stop control in the supervisor UI, or another available mechanism).
- Recognize what the system displays when a device goes offline.
- Produce a coherent written assessment, not just a log dump.

---

## Verification Approach

Verification uses the **"new log lines only"** approach: only log entries written after task setup began count toward scoring. The setup script records the initial log file size; the export script reads only bytes written after that offset.

File timestamps use `int(mtime) > task_start` for comparison (integer seconds since epoch).

### Evidence Checked

| Evidence | How Checked |
|---|---|
| 2+ Multiparameter Monitor creation events | Regex count on new log bytes |
| Vital Signs app launched | Regex on new log bytes |
| Window count decreased (device stopped) | `wmctrl -l` count at end vs. initial |
| 3rd device creation event (recovery) | Regex count >= 3 in new log |
| Report file exists with adequate content | File present, mtime > task_start, size >= 300 bytes |
| Report quality: failure + recovery + assessment terminology | `grep -q` binary flags per keyword group |

Binary flag checks use `grep -q` only — never `grep -c pattern file || echo "0"`.

---

## Scoring Breakdown (100 points total)

| Criterion | Points | Condition |
|---|---|---|
| Initial dual device setup | 20 | 2+ Multiparameter Monitor creation events in new log |
| Vital Signs app launched | 15 | Vital Signs launch detected in new log |
| Device failure simulated | 20 | Evidence a device window was closed/stopped |
| Device recovery | 20 | 3rd device creation event in new log |
| Fault tolerance report exists | 15 | File present, modified after task start, >= 300 bytes |
| Report quality | 10 | Fault/failure terminology (3) + recovery (3) + assessment (2) + dual-device mention (2) |

**Pass threshold:** 60 points

### GATE Rule

If the fault tolerance report does **not** exist AND the raw score would be >= 60 (pass threshold), the score is capped at 59. The written report is a required deliverable for clinical validation; achieving a technical score without documentation does not constitute a passing test.

---

## Files

| File | Purpose |
|---|---|
| `README.md` | This documentation |
| `task.json` | Task definition, metadata, and success spec |
| `setup_task.sh` | Pre-task setup: timestamps, log baseline, window baseline |
| `export_result.sh` | Post-task export: collect all evidence into `/tmp/task_result.json` |
| `verifier.py` | Score computation from collected evidence |

---

## Setup Details

`setup_task.sh` records:
- `/tmp/task_start_timestamp` — Unix epoch second at task start
- `/tmp/initial_log_size` — byte offset in openice.log at task start
- `/tmp/initial_window_count` — number of X11 windows at task start
- `/tmp/initial_window_list` — snapshot of window list for reference

It also removes any pre-existing fault_tolerance_report.txt so the agent cannot reuse a stale file.

---

## Notes for Task Designers

- The device type targeted is "Simulated Multiparameter Monitor" (matched by regex: `multiparameter|multiParam|multiparammonitor`, case-insensitive).
- The log path is `/home/ga/openice/logs/openice.log`.
- Window count heuristic is a proxy for device adapter windows being open/closed; it is combined with log evidence for robustness.
- Partial credit is awarded at most scoring criteria so the score reflects how far the agent progressed through the procedure.
