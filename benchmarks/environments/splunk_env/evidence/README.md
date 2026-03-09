# Splunk Enterprise Environment - Evidence Documentation

## Environment Overview

- **Environment ID**: `splunk_env@0.1`
- **Application**: Splunk Enterprise 9.4.0
- **Base Image**: `ubuntu-gnome-systemd_highres`
- **Resources**: 4 CPU, 8 GB RAM, no GPU, network enabled
- **Credentials**: `admin / SplunkAdmin1!`
- **Web UI**: `http://localhost:8000`
- **REST API**: `https://localhost:8089`

## Audit Fixes Applied (2026-01-30)

### CRITICAL: Task Start State Fix (Fourth Audit)

**Issue**: `setup_task.sh` scripts continued execution even when `ensure_firefox_with_splunk` failed. Scripts logged "WARNING: Proceeding despite failure" instead of exiting, resulting in invalid task start states.

**Fixes Applied**:

1. **`setup_task.sh` scripts now EXIT on verification failure**:
   ```bash
   if ! ensure_firefox_with_splunk 120; then
       echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
       echo "Task setup FAILED - task start state is INVALID"
       take_screenshot /tmp/task_start_screenshot_FAILED.png
       # EXIT WITH ERROR - Do not continue with invalid state
       exit 1
   fi
   ```

2. **`ensure_firefox_with_splunk()` returns 1 on failure** (`task_utils.sh`):
   ```bash
   if [ "$verified" = true ]; then
       return 0
   else
       echo "=== CRITICAL FAILURE: Could not verify Splunk in Firefox ==="
       return 1  # NOT return 0!
   fi
   ```

3. **Timeout increased to 120 seconds** (was 30-60):
   - Default timeout is now 120 seconds
   - Additional 30 seconds after page refresh attempt

4. **Screenshot taken ONLY AFTER successful verification**:
   - Additional 3-second wait after verification
   - Screenshot captures the verified state
   - Failed states get a separate screenshot with _FAILED suffix

### HIGH: Task Descriptions Updated (Fourth Audit)

**Issue**: Task description for create_alert said "search query like:" suggesting flexibility, but verifier strictly requires specific elements.

**Fixes Applied**:

All task descriptions now:
- "First, log in to Splunk using username 'admin' and password 'SplunkAdmin1!'"
- Changed "search query like:" to "enter the search query:" (no ambiguity)
- Login step is the first action mentioned
- Search task uses example format "(e.g., index=security_logs Failed)"

### MEDIUM: Threshold Now Enforced in create_alert

**Issue**: Task description said "more than 5 failed attempts" but verifier only checked for threshold as informational.

**Fix Applied** (`create_alert/verifier.py`):
- Added 5th criterion: `has_threshold` is now REQUIRED
- Task only passes if search contains threshold pattern (e.g., `where count > 5`)
- Total criteria increased from 4 to 5
- Pass condition: `criteria_met >= 5`

## Verification Checklist

### Installation (pre_start hook)
- [x] Splunk Enterprise 9.4.0 downloaded and installed via .deb package
- [x] Dependencies installed (curl, jq, firefox, wmctrl, xdotool, scrot)
- [x] Admin credentials pre-seeded via user-seed.conf
- [x] Web interface configured for HTTP on port 8000
- [x] Real-world log data downloaded from Loghub (Zenodo)

### Setup (post_start hook)
- [x] Splunk started non-interactively with license accepted
- [x] Web interface accessible (HTTP 303 redirect to login)
- [x] REST API accessible on port 8089
- [x] Custom indexes created: security_logs, web_logs, system_logs, tutorial, network_logs
- [x] Real-world data ingested into indexes
- [x] Live system log monitoring configured (/var/log/syslog, /var/log/auth.log)
- [x] Pre-built saved search "Failed_SSH_Logins" created
- [x] Firefox configured with profile (no first-run dialogs)
- [x] Firefox launched and maximized with Splunk homepage

### Task Start State (FIXED - Fourth Audit)
- [x] `ensure_firefox_with_splunk()` returns 1 (failure) if Splunk not verified
- [x] Timeout increased to 120 seconds minimum
- [x] `setup_task.sh` scripts EXIT with code 1 on verification failure (not just log)
- [x] Screenshot taken ONLY AFTER successful verification
- [x] Task descriptions explicitly mention login step
- [x] Removed "like:" language from task descriptions (no ambiguity)

### Data Ingestion
- [x] **security_logs index**: 655,654 events (real OpenSSH server logs from Loghub - 73 MB)
- [x] **web_logs index**: 52,004 events (real Apache error logs from Loghub - 5 MB)
- [x] **system_logs index**: 36,491 events (real Linux syslog from Loghub + live VM logs)

## Data Sources

All data is real-world data from established research datasets:

| Source | Dataset | Origin | Size | License |
|--------|---------|--------|------|---------|
| SSH.log | OpenSSH server logs (655K events) | [Loghub/Zenodo](https://zenodo.org/records/8196385) | 73 MB | Research use |
| Apache.log | Apache error logs (52K events) | [Loghub/Zenodo](https://zenodo.org/records/8196385) | 5 MB | Research use |
| Linux.log | Linux syslog (25K events) | [Loghub/Zenodo](https://zenodo.org/records/8196385) | 2.3 MB | Research use |
| Live syslog | VM's own /var/log/syslog | Live system | Continuous | N/A |
| Live auth.log | VM's own /var/log/auth.log | Live system | Continuous | N/A |

## Verifier Strictness (Post-Fifth-Audit)

### search_security_events Verifier

**STRICT Requirements (ALL 4 programmatic criteria required to pass):**
1. New search jobs must be created
2. Search query MUST contain `security_logs` index reference
3. Search query MUST contain `failed` keyword AND return >= 10 events
4. Search must complete with status DONE/FINALIZED/COMPLETED

**VLM Verification (Bonus - reported in subscores):**
5. VLM confirms Splunk web UI was used for search

### create_alert Verifier

**STRICT Requirements (ALL 5 programmatic criteria required to pass):**
1. A new alert must be created
2. Alert name MUST be exactly "Brute_Force_Detection" (normalized)
3. Alert search MUST contain both `security_logs` AND `failed`
4. Alert MUST be scheduled with cron `*/5 * * * *`
5. Alert search MUST contain threshold (e.g., `where count > 5`) - STRICTER regex now

**VLM Verification (Bonus - reported in subscores):**
6. VLM confirms Splunk web UI was used for alert creation

### add_data_source Verifier

**STRICT Requirements (ALL required to pass):**
1. Monitor must be detected via REST API
2. Monitor path MUST be exactly `/var/log/kern.log`
3. Monitor MUST use `system_logs` index (NOT `main`)
4. Sourcetype should be appropriate (lenient)

**VLM Verification (Bonus - reported in subscores):**
5. VLM confirms Splunk web UI was used for data input configuration

## Tasks

### 1. search_security_events (Medium)
Search for failed SSH login attempts in the security_logs index.

**Steps:**
1. Log in to Splunk (admin / SplunkAdmin1!)
2. Navigate to Search & Reporting
3. Enter query containing `index=security_logs` AND `Failed`
4. Execute search and view results

### 2. create_alert (Hard)
Create a brute force detection alert.

**Steps:**
1. Log in to Splunk (admin / SplunkAdmin1!)
2. Navigate to Search & Reporting
3. Enter search: `index=security_logs "Failed password" | stats count by src_ip | where count > 5`
4. Save as alert named "Brute_Force_Detection"
5. Schedule with cron `*/5 * * * *`

### 3. add_data_source (Medium)
Add a file monitor for /var/log/kern.log.

**Steps:**
1. Log in to Splunk (admin / SplunkAdmin1!)
2. Navigate to Settings > Data Inputs > Files & Directories
3. Add monitor for `/var/log/kern.log`
4. Set index to `system_logs` (NOT `main`)

## Audit History

| Date | Audit # | Status | Key Issues |
|------|---------|--------|------------|
| 2026-01-30 | 1 | FAIL | Verifiers too lenient, task start state |
| 2026-01-30 | 2 | FAIL | ensure_firefox_with_splunk returns 0 on failure |
| 2026-01-30 | 3 | FAIL | setup_task.sh continues despite verification failure |
| 2026-01-30 | 4 | FAIL | Task start screenshots show login page not home, no VLM verification |
| 2026-01-30 | 5 | FIXED | All critical issues addressed |

### Fifth Audit Fixes Summary

1. **CRITICAL**: Task start state screenshot inconsistency investigated - screenshots were from prior audits
2. **HIGH**: Added VLM-based UI verification to ALL three verifiers
   - `search_security_events`: Verifies Splunk web UI used, search interface interacted with
   - `create_alert`: Verifies alert creation UI used, alert name visible
   - `add_data_source`: Verifies data input UI used, file path visible
3. **MEDIUM**: Tightened threshold check regex in `create_alert/verifier.py`:
   - Removed overly lenient `r'\|\s*where\s+'` pattern that matched ANY where clause
   - Now requires actual numeric comparison: `count > N`, `where count >= N`, etc.
4. **NOTE**: VLM verification is trajectory-based using `sample_trajectory_frames()` for process verification
5. **NOTE**: VLM criterion is non-blocking (programmatic criteria still required to pass)

### VLM Verification Details

All three verifiers now include VLM-based UI verification:

```python
# Get trajectory frames for process verification
frames = sample_trajectory_frames(traj, num_samples=5)
final_screenshot = get_final_screenshot(traj)

vlm_result = query_vlm(
    prompt=UI_VERIFICATION_PROMPT,
    images=images_to_check,
)
```

This provides an independent verification channel that:
- Confirms the agent used the web UI, not just REST API or CLI
- Uses multiple trajectory frames (not just final screenshot) for process verification
- Reports UI verification status in subscores (`vlm_ui_verified`)

### Fourth Audit Fixes Summary

1. **CRITICAL**: `setup_task.sh` scripts now `exit 1` on verification failure (not just log warning)
2. **CRITICAL**: Removed "WARNING: Proceeding despite failure" code path entirely
3. **HIGH**: Removed "like:" language from task descriptions (no ambiguity)
4. **MEDIUM**: Threshold check now required in create_alert verifier (5 criteria)
5. **LOW**: Screenshot only taken after successful verification
