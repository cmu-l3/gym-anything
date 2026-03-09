# Thunderbird Environment - Evidence Documentation

## Environment Overview

- **Environment ID**: `thunderbird_env@0.1`
- **Application**: Mozilla Thunderbird email client (v128.12.0esr)
- **Base Image**: `ubuntu-gnome-systemd_highres` (1920x1080)
- **Resources**: 4 CPU, 4GB RAM, no GPU, network enabled
- **Clean E2E Test Date**: 2026-01-26 12:10 UTC (re-run with VLM-hybrid verifiers)

## Tasks

| Task | Difficulty | Timeout | Max Steps | Description |
|------|-----------|---------|-----------|-------------|
| `compose_send_email` | easy | 120s | 25 | Compose email and save as draft |
| `organize_emails_into_folders` | medium | 150s | 35 | Create "Important" folder, move emails |
| `create_mail_filter` | medium | 180s | 40 | Create filter: subject "urgent" -> move to "Urgent" folder |

## Data Source

- **Source**: SpamAssassin Public Corpus (https://spamassassin.apache.org/old/publiccorpus/)
- **Ham emails**: 50 real emails from `20030228_easy_ham.tar.bz2`
- **Spam emails**: 20 real emails from `20030228_spam.tar.bz2`
- **Format**: RFC 2822, imported into Thunderbird mbox format
- **License**: Public domain research corpus

---

## Verification Architecture

All 3 verifiers use a **hybrid multi-signal verification** pattern combining:
- **Programmatic verification** (65-75 points): File-based checks on JSON exported from VM
- **VLM visual verification** (25 points): Trajectory frame analysis (15 pts) + final screenshot check (10 pts)

VLM verification uses `env_info.get('query_vlm')` and `env_info.get('sample_trajectory_frames')` to analyze agent interaction screenshots. When VLM is not available (e.g., mock tests), verifiers gracefully degrade to programmatic-only scoring. Pass thresholds are set so tasks can pass with programmatic-only scores.

---

## Checklist Evidence

All evidence below is from actual VM runs captured during the clean E2E test on 2026-01-26. No mock or fake data.

### 1. Installation Script Completes Without Errors

**Status**: PASS

**Actual pre_start hook log** (captured via SSH from `/home/ga/env_setup_pre_start.log`, 17,375 bytes):

```
=== Installing Mozilla Thunderbird ===
Get:1 http://security.ubuntu.com/ubuntu jammy-security InRelease [129 kB]
...
Fetched 39.8 MB in 4s (9,258 kB/s)
Reading package lists...
Building dependency tree...
The following NEW packages will be installed:
  jq libid3tag0 libimlib2 libjq1 libonig5 python3-pip-whl
  python3-setuptools-whl python3-venv python3.10-venv scrot sqlite3
  thunderbird
7 upgraded, 12 newly installed, 0 to remove and 68 not upgraded.
Need to get 92.5 MB of archives.
...
Setting up thunderbird (1:128.12.0+build1-0ubuntu0.22.04.1) ...
Setting up scrot (1.7-1) ...
Setting up sqlite3 (3.37.2-2ubuntu0.5) ...
Setting up jq (1.6-2.1ubuntu3.1) ...
...
Thunderbird binary found at: /usr/bin/thunderbird
=== Mozilla Thunderbird installation complete ===
```

**Full log**: See `pre_start_hook_log.txt` (17,473 bytes)

**Verification via SSH**:
```
$ which thunderbird
/usr/bin/thunderbird

$ thunderbird --version
Thunderbird 128.12.0esr
```

---

### 2. Setup Script Completes Without Errors

**Status**: PASS

**Actual post_start hook log** (captured via SSH from `/home/ga/env_setup_post_start.log`):

```
=== Setting up Mozilla Thunderbird ===
Importing email data into local folders...
Imported 50 ham emails into Inbox
Imported 20 spam emails into Junk
=== Mozilla Thunderbird setup complete ===
Profile: /home/ga/.thunderbird/default-release
Inbox emails: 50
Junk emails: 20
Local folders: Inbox, Junk, Drafts, Sent, Trash, Templates
```

**Full log**: See `post_start_hook_log.txt` (429 bytes)

**Profile directory listing** (via SSH):
```
$ ls -la /home/ga/.thunderbird/default-release/
total 20
drwxr-xr-x 4 ga ga 4096 Jan 26 15:44 .
drwxr-xr-x 5 ga ga 4096 Jan 26 15:44 ..
drwxr-xr-x 2 ga ga 4096 Jan 26 15:44 ImapMail
drwxr-xr-x 3 ga ga 4096 Jan 26 15:44 Mail
-rw-r--r-- 1 ga ga 2365 Jan 26 15:44 user.js
```

---

### 3. Application Is Visible in Screenshot

**Status**: PASS

**Screenshots from actual E2E test**:
- `e2e_boot_screenshot.png` - Ubuntu desktop after boot (Thunderbird icon visible in taskbar)
- `e2e_compose_send_email_ready.png` - Thunderbird running for compose task
- `e2e_organize_emails_into_folders_ready.png` - Thunderbird running for organize task
- `e2e_create_mail_filter_ready.png` - Thunderbird running for filter task
- `thunderbird_inbox_with_emails.png` - Inbox selected, showing 50+ email subjects in list view
- `thunderbird_junk_with_emails.png` - Junk folder selected, showing 20 spam emails in list view

**Window detection** (via `wmctrl -l` during task run):
```
0x02000003 -1 ga-base @!0,0;BDHF
0x0080002c  0 ga-base Local Folders - Mozilla Thunderbird
```

Thunderbird window title "Local Folders - Mozilla Thunderbird" confirms the application is running and visible. Inbox and Junk folder screenshots (navigated via CUA-guided xdotool clicks) confirm emails are loaded and visible in the GUI.

---

### 4. Application Is in Correct Initial State

**Status**: PASS

**Verified via SSH during clean E2E test**:
```
$ grep -c "^From " "/home/ga/.thunderbird/default-release/Mail/Local Folders/Inbox"
50

$ grep -c "^From " "/home/ga/.thunderbird/default-release/Mail/Local Folders/Junk"
20
```

**Boot test state** (from `boot_test_state.json`):
```json
{
  "test": "boot_test",
  "ssh_port": 2235,
  "thunderbird_path": "/usr/bin/thunderbird",
  "thunderbird_version": "Thunderbird 128.12.0esr",
  "inbox_count": "50",
  "junk_count": "20",
  "thunderbird_running": true,
  "windows": "0x02000003 -1 ga-base @!0,0;BDHF",
  "pre_start_log_size": 17375,
  "post_start_log_size": 332
}
```

**Visual confirmation of email visibility** (via CUA-guided GUI interaction):
- `thunderbird_inbox_with_emails.png` — Inbox selected, title bar shows "Inbox - Local Folders - Mozilla Thunderbird", 50+ emails visible in list view with subjects from SpamAssassin corpus
- `thunderbird_junk_with_emails.png` — Junk folder selected, title bar shows "Junk - Local Folders - Mozilla Thunderbird", 20 spam emails visible in list view

---

### 5. Task Setup Runs Without Errors

**Status**: PASS

All three tasks ran with pre_task hooks logged at `/home/ga/task_pre_task.log`:

**Framework output** (from actual E2E test log):
```
[gym-anything] Running pre_start hook...
[gym-anything] Running post_start hook...
Profiling time for env setup: 44.55s
[gym-anything] Running pre_task hook...
Profiling time for task specific hooks: 12.01s
```

All task setup scripts complete within ~12s (includes 8s Thunderbird startup + window wait).

**Log files present in VM** (verified via SSH):
```
-rw-rw-r-- 1 ga ga   332 Jan 26 15:45 /home/ga/env_setup_post_start.log
-rw-rw-r-- 1 ga ga 17374 Jan 26 15:45 /home/ga/env_setup_pre_start.log
-rw-rw-r-- 1 ga ga   182 Jan 26 15:45 /home/ga/task_pre_task.log
```

---

### 6. Export Script Produces Valid JSON

**Status**: PASS

All three `export_result.sh` scripts produce well-formed JSON. Actual outputs from clean E2E test:

**compose_send_email** (from `export_compose_send_email_output.txt`):
```
=== Exporting compose_send_email result ===
Result saved to /tmp/task_result.json
{
    "draft_added": false,
    "initial_drafts_count": 0,
    "current_drafts_count": 0,
    "draft_recipient": "",
    "draft_subject": "",
    "draft_body_snippet": "",
    "sent_count": 0,
    "outbox_exists": true,
    "outbox_count": 0,
    "compose_window_opened": false,
    "thunderbird_running": true,
    "timestamp": "2026-01-26T15:45:58+00:00"
}
=== Export complete ===
```

**organize_emails_into_folders** (from `export_organize_emails_into_folders_output.txt`):
```
=== Exporting organize_emails_into_folders result ===
Result saved to /tmp/task_result.json
{
    "folder_created": false,
    "folder_email_count": 0,
    "folder_path": "",
    "initial_inbox_count": 50,
    "current_inbox_count": 50,
    "emails_moved_from_inbox": 0,
    "current_folders": "Drafts,Inbox,Junk,Sent,Templates,Trash,Unsent Messages",
    "thunderbird_running": true,
    "timestamp": "2026-01-26T15:47:27+00:00"
}
=== Export complete ===
```

**create_mail_filter** (from `export_create_mail_filter_output.txt`):
```
=== Exporting create_mail_filter result ===
Result saved to /tmp/task_result.json
{
    "filter_created": false,
    "initial_filter_count": 0,
    "current_filter_count": 0,
    "filter_name": "",
    "filter_condition": "",
    "filter_action": "",
    "filter_target": "",
    "urgent_folder_exists": false,
    "thunderbird_running": true,
    "timestamp": "2026-01-26T15:48:49+00:00"
}
=== Export complete ===
```

---

### 7. Verifier Can Read and Process the Result

**Status**: PASS

All three verifiers were executed on the host side during the E2E test. Each verifier:
1. Used `copy_from_env` to copy `/tmp/task_result.json` from VM to a temp file on host
2. Parsed the JSON successfully
3. Evaluated criteria and returned structured results

**copy_from_env confirmed working** (from E2E log):
```
[E2E] Copied task_result.json from VM to /tmp/tmp3izhwi67.json
[E2E] Verified JSON is readable on host
```

**compose_send_email verifier result** (baseline — no agent interaction):
```
passed=False, score=10
feedback: No new draft found in Drafts folder | No recipient found in draft | Subject doesn't match: got '' |
  No body content found in draft | Thunderbird running |
  VLM: Trajectory verification not available | VLM: Not available
```

**organize_emails_into_folders verifier result** (baseline — no agent interaction):
```
passed=False, score=10
feedback: 'Important' folder not created | Folder is empty (needs 3 emails) | No emails moved from Inbox |
  Thunderbird running |
  VLM: Trajectory verification not available | VLM: Not available
```

**create_mail_filter verifier result** (baseline — no agent interaction):
```
passed=False, score=10
feedback: No new filter found in msgFilterRules.dat | No filter condition found | No filter action found |
  Filter target doesn't match Urgent folder: | Thunderbird running |
  VLM: Trajectory verification not available | VLM: Not available
```

All baseline scores are 10 (only "Thunderbird running" criterion met). VLM checks are skipped in baseline (no agent trajectory available), reporting "Trajectory verification not available" and "Not available".

---

### 8. Verification Returns Expected Result

**Status**: PASS

#### Baseline Test (No Agent Interaction)

The baseline test correctly returns `passed: false` for all tasks. Scores reflect programmatic-only evaluation (VLM not exercised in baseline — no agent trajectory):

| Task | Score | Key Criterion | Expected Baseline |
|------|-------|--------------|-------------------|
| compose_send_email | 10 | Only TB running (10 pts) | Correct — fails |
| organize_emails_into_folders | 10 | Only TB running (10 pts) | Correct — fails |
| create_mail_filter | 10 | Only TB running (10 pts) | Correct — fails |

#### Correct Completion Test (Task Completed in Real VM)

After completing each task in a real VM, verifiers return `passed: true` with programmatic scores meeting pass thresholds:

| Task | Score | Pass Threshold | Passed |
|------|-------|---------------|--------|
| compose_send_email | 75 | ≥ 60 | ✅ true |
| create_mail_filter | 70 | ≥ 50 | ✅ true |
| organize_emails_into_folders | 65 | ≥ 50 | ✅ true |

All verifier results are from **actual exported data** (not mock). With VLM available via agent trajectory, scores would reach 90-100. See "Correct Completion Tests" section for full details.

---

### 9. Verifier Mock Tests (Do-Nothing, Partial, Correct, Wrong-Params)

**Status**: PASS (12/12 tests across all 3 verifiers)

Each verifier includes a `__main__` test block with 4 mock test scenarios. All tests run locally without a VM. Scores below are **programmatic-only** (VLM not available in mock tests — VLM criteria report "VLM: Trajectory verification not available" and "VLM: Not available").

**Full output**: See `verifier_mock_tests_output.txt`

**compose_send_email** (4/4 passed) — pass threshold: score ≥ 60 AND draft_added:
| Test | Score | Passed | Expected |
|------|-------|--------|----------|
| Do nothing | 10 | false | score<=25, fail |
| Partial (wrong recipient/subject) | 35 | false | score<60, fail |
| Correct completion | 75 | true | score>=60, pass |
| Wrong parameters (wrong email/subject) | 35 | false | fail |

**organize_emails_into_folders** (4/4 passed) — pass threshold: score ≥ 50 AND folder_created AND folder_count ≥ min_emails:
| Test | Score | Passed | Expected |
|------|-------|--------|----------|
| Do nothing | 10 | false | score<=20, fail |
| Partial (folder created, empty) | 30 | false | score<50, fail |
| Correct completion (5 emails moved) | 65 | true | score>=55, pass |
| Wrong parameters (wrong folder name) | 25 | false | fail |

**create_mail_filter** (4/4 passed) — pass threshold: score ≥ 50 AND filter_created AND urgent_folder_targeted:
| Test | Score | Passed | Expected |
|------|-------|--------|----------|
| Do nothing | 10 | false | score<=20, fail |
| Partial (folder only, no filter) | 15 | false | score<50, fail |
| Correct completion (filter + folder) | 70 | true | score>=60, pass |
| Wrong parameters (filter for 'spam') | 45 | false | fail |

**Note**: With VLM available (real agent trajectory), correct completion scores would reach up to 90-100 (programmatic + VLM trajectory + VLM final state).

---

## Bugs Fixed During Development

### Bug 1: Integer Comparison Error in `count_emails_in_mbox`

**Symptom**: `[: 0\n0: integer expression expected` during export_result.sh
**Cause**: `grep -c` returned count with trailing newline; bash integer comparison failed
**Fix**: Added whitespace stripping and integer validation in `task_utils.sh`

### Bug 2: Empty String Subject Match in compose_send_email verifier

**Symptom**: Verifier gave "Correct subject: " score for empty subject (score 40% instead of 20%)
**Cause**: Python `"" in "q4 budget review meeting"` is always True
**Fix**: Added `if actual_subject and ...` guard before substring check

---

## Evidence Files Inventory

### Screenshots (from actual QEMU VM runs)

| File | Size | Description |
|------|------|-------------|
| `e2e_boot_screenshot.png` | 1.9MB | Ubuntu desktop after clean boot |
| `e2e_compose_send_email_ready.png` | 896KB | Thunderbird ready for compose task |
| `e2e_organize_emails_into_folders_ready.png` | 897KB | Thunderbird ready for organize task |
| `e2e_create_mail_filter_ready.png` | 896KB | Thunderbird ready for filter task |
| `thunderbird_running.png` | 896KB | Thunderbird main window (earlier test) |
| `thunderbird_inbox_with_emails.png` | ~900KB | Inbox selected with 50 emails visible in list view |
| `thunderbird_junk_with_emails.png` | ~900KB | Junk folder selected with 20 spam emails visible |

### Hook Logs (captured via SSH from actual VMs)

| File | Size | Description |
|------|------|-------------|
| `pre_start_hook_log.txt` | 17KB | Full apt-get install output, package listing |
| `post_start_hook_log.txt` | 429B | Profile setup, email import counts |

### Export Script Outputs (run inside actual VMs)

| File | Size | Description |
|------|------|-------------|
| `export_compose_send_email_output.txt` | 561B | Full export script stdout |
| `export_organize_emails_into_folders_output.txt` | 562B | Full export script stdout |
| `export_create_mail_filter_output.txt` | 511B | Full export script stdout |

### Task Result JSONs (copied from VMs via SSH)

| File | Size | Description |
|------|------|-------------|
| `task_result_compose_send_email.json` | 334B | Baseline task result |
| `task_result_organize_emails_into_folders.json` | 321B | Baseline task result |
| `task_result_create_mail_filter.json` | 288B | Baseline task result |

### Verifier Results (run on host, reading from VMs via copy_from_env)

| File | Size | Description |
|------|------|-------------|
| `verifier_result_compose_send_email.json` | 351B | Baseline score: 10, passed: false |
| `verifier_result_organize_emails_into_folders.json` | 368B | Baseline score: 10, passed: false |
| `verifier_result_create_mail_filter.json` | 448B | Baseline score: 10, passed: false |

### Verifier Mock Tests

| File | Size | Description |
|------|------|-------------|
| `verifier_mock_tests_output.txt` | ~4KB | All 12 mock tests (4 per verifier) output |

### Correct Completion Evidence (from real VM task execution)

| File | Description |
|------|-------------|
| `correct_completion_test_log.txt` | Full test execution log for all 3 tasks |
| `correct_completion_summary.json` | Summary: all 3 tasks passed (75/70/65 programmatic) |
| `correct_completion_task1_before.png` | Before: Inbox selected, 50 emails visible in list view |
| `correct_completion_task1_after.png` | After: Drafts folder selected, 1 draft ("Q4 Budget Review Meeting") visible |
| `correct_completion_task1_export.txt` | Export script output for compose_send_email |
| `correct_completion_task1_result.json` | Task result JSON from VM for compose_send_email |
| `correct_completion_task1_verifier.json` | Verifier result: passed=true, score=75 (programmatic) |
| `correct_completion_task2_before.png` | Before: Inbox selected, 50 emails visible in list view |
| `correct_completion_task2_after.png` | After: Folder tree shows new "Urgent" folder in sidebar |
| `correct_completion_task2_export.txt` | Export script output for create_mail_filter |
| `correct_completion_task2_result.json` | Task result JSON from VM for create_mail_filter |
| `correct_completion_task2_verifier.json` | Verifier result: passed=true, score=70 (programmatic) |
| `correct_completion_task3_before.png` | Before: Inbox selected, 50 emails visible in list view |
| `correct_completion_task3_after.png` | After: "Important" folder selected, 5 moved emails visible |
| `correct_completion_task3_export.txt` | Export script output for organize_emails |
| `correct_completion_task3_result.json` | Task result JSON from VM for organize_emails |
| `correct_completion_task3_verifier.json` | Verifier result: passed=true, score=65 (programmatic) |

### Test Logs

| File | Size | Description |
|------|------|-------------|
| `e2e_test_log.txt` | 11KB | E2E test log (from earlier verifier version; scores in log are outdated — see Section 8 for current baseline scores) |
| `boot_test_state.json` | 329B | Environment state after boot |

---

## Correct Completion Tests (Real Data, Not Mock)

**Date**: 2026-01-26
**Requirement**: Phase 5.5 of prompt.md: "Verifier should be tested on actual files exported from the environment, and never on fake or mock data."

Each task was completed in an actual QEMU VM by manipulating Thunderbird's file state (mbox files, filter rules), then the **real export scripts** ran inside the VM reading **real Thunderbird files**, and the **real verifiers** ran on the host reading the **actual exported JSON** via `copy_from_env`.

**Before/after screenshots** were captured using xdotool-based folder navigation (CUA-verified coordinates at 1920x1080). Before screenshots show Inbox with 50 emails; after screenshots navigate to the task-specific folder to visually confirm state changes:

### Task 1: compose_send_email — PASSED (Score: 75/75 programmatic)

**VM Instance**: `ga_qemu_f3a6b2448a01` (SSH port 2326)

**What was done**: Draft email written to Thunderbird's Drafts mbox file in proper mbox format with correct headers (To: colleague@example.com, Subject: Q4 Budget Review Meeting, body with budget/meeting/Q4 keywords). Thunderbird was stopped before mbox modification, lock/index files cleaned, then restarted.

**Export script output** (from `correct_completion_task1_export.txt`):
```json
{
    "draft_added": true,
    "initial_drafts_count": 0,
    "current_drafts_count": 1,
    "draft_recipient": "colleague@example.com",
    "draft_subject": "Q4 Budget Review Meeting",
    "draft_body_snippet": "I would like to schedule a meeting to discuss our Q4 budget allocations and review the quarterly financial targets. Please let me know your availability for next week.  Best regards",
    "sent_count": 0,
    "outbox_exists": true,
    "outbox_count": 0,
    "compose_window_opened": false,
    "thunderbird_running": true,
    "timestamp": "2026-01-26T19:00:14+00:00"
}
```

**Verifier result** (from `correct_completion_task1_verifier.json`):
```json
{
  "passed": true,
  "score": 75,
  "feedback": "Draft saved successfully | Correct recipient: colleague@example.com | Correct subject: Q4 Budget Review Meeting | All 3 keywords found in body | Thunderbird running | VLM: Trajectory verification not available | VLM: Not available",
  "details": {
    "draft_added": true,
    "recipient": "colleague@example.com",
    "subject": "Q4 Budget Review Meeting",
    "body_snippet": "I would like to schedule a meeting to discuss our Q4 budget allocations and review the quarterly fin",
    "vlm_compose_verified": false,
    "vlm_final_verified": false,
    "score_breakdown": {
      "programmatic": 75,
      "vlm": 0
    }
  }
}
```

### Task 2: create_mail_filter — PASSED (Score: 70/70 programmatic)

**VM Instance**: `ga_qemu_f7a6220562c4` (SSH port 2388)

**What was done**: Created `msgFilterRules.dat` with Urgent Filter (subject contains "urgent" → Move to folder Urgent) and created the Urgent mbox folder file. Thunderbird was stopped before file modification, lock files cleaned, then restarted.

**Export script output** (from `correct_completion_task2_export.txt`):
```json
{
    "filter_created": true,
    "initial_filter_count": 0,
    "current_filter_count": 1,
    "filter_name": "Urgent Filter",
    "filter_condition": "AND (subject,contains,urgent)",
    "filter_action": "Move to folder",
    "filter_target": "mailbox://nobody@Local Folders/Urgent",
    "urgent_folder_exists": true,
    "thunderbird_running": true,
    "timestamp": "2026-01-26T19:02:03+00:00"
}
```

**Verifier result** (from `correct_completion_task2_verifier.json`):
```json
{
  "passed": true,
  "score": 70,
  "feedback": "Filter created: 'Urgent Filter' | Correct filter condition: subject contains 'urgent' | Filter action is 'Move to folder' | Filter targets 'Urgent' folder | Thunderbird running | VLM: Trajectory verification not available | VLM: Not available",
  "details": {
    "filter_created": true,
    "filter_name": "Urgent Filter",
    "filter_condition": "AND (subject,contains,urgent)",
    "filter_action": "Move to folder",
    "filter_target": "mailbox://nobody@Local Folders/Urgent",
    "urgent_folder_exists": true,
    "vlm_trajectory_verified": false,
    "vlm_final_verified": false,
    "score_breakdown": {
      "programmatic": 70,
      "vlm": 0
    }
  }
}
```

### Task 3: organize_emails_into_folders — PASSED (Score: 65/65 programmatic)

**VM Instance**: `ga_qemu_e6c04da86c18` (SSH port 2324)

**What was done**: Created "Important" mbox folder, moved 5 real emails from Inbox (50 → 45) into Important folder using Python mbox splitting. Thunderbird was stopped before mbox modification, lock/index files cleaned, then restarted.

**Export script output** (from `correct_completion_task3_export.txt`):
```json
{
    "folder_created": true,
    "folder_email_count": 5,
    "folder_path": "/home/ga/.thunderbird/default-release/Mail/Local Folders/Important",
    "initial_inbox_count": 50,
    "current_inbox_count": 45,
    "emails_moved_from_inbox": 5,
    "current_folders": "Drafts,Important,Inbox,Junk,Sent,Templates,Trash,Unsent Messages",
    "thunderbird_running": true,
    "timestamp": "2026-01-26T19:03:32+00:00"
}
```

**Verifier result** (from `correct_completion_task3_verifier.json`):
```json
{
  "passed": true,
  "score": 65,
  "feedback": "'Important' folder created | Folder contains 5 emails (required: 3) | 5 emails moved from Inbox | Thunderbird running | VLM: Trajectory verification not available | VLM: Not available",
  "details": {
    "folder_created": true,
    "folder_email_count": 5,
    "emails_moved": 5,
    "initial_inbox": 50,
    "current_inbox": 45,
    "vlm_trajectory_verified": false,
    "vlm_final_verified": false,
    "score_breakdown": {
      "programmatic": 65,
      "vlm": 0
    }
  }
}
```

### Correct Completion Summary

| Task | Programmatic Score | VLM Score | Total | Passed | VM Instance |
|------|-------------------|-----------|-------|--------|-------------|
| compose_send_email | 75/75 | 0 (not available) | 75 | ✅ true | ga_qemu_f3a6b2448a01 |
| create_mail_filter | 70/70 | 0 (not available) | 70 | ✅ true | ga_qemu_f7a6220562c4 |
| organize_emails_into_folders | 65/65 | 0 (not available) | 65 | ✅ true | ga_qemu_e6c04da86c18 |

**All 3 tasks pass correct completion verification using actual data exported from real VMs.**

*Note*: Correct completion tests were run with programmatic-only verification (no agent trajectory available for VLM). With a real agent trajectory, VLM criteria would add up to 25 additional points per task. The pass thresholds (60, 50, 50) are set such that programmatic criteria alone are sufficient to pass when task is correctly completed.

---

## Baseline E2E Test Summary

Test ran 4 separate VM instances (1 boot test + 3 task tests) with NO agent interaction (baseline):

| Test | Instance | SSH Port | Setup Time | Result |
|------|----------|----------|------------|--------|
| Boot test (no task) | `ga_qemu_f0db7bc2cd1f` | 2235 | 43s | PASS |
| compose_send_email | `ga_qemu_1365531e7183` | 2348 | 57s (45s env + 12s task) | PASS |
| organize_emails_into_folders | `ga_qemu_c361d15ffc5c` | 2378 | 80s (67s env + 13s task) | PASS |
| create_mail_filter | `ga_qemu_9ef15d19c99b` | 2295 | 73s (61s env + 12s task) | PASS |

All VM instances started, ran hooks, launched Thunderbird, exported valid JSON, and verifiers processed results correctly.
