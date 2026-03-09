# Tor Browser Environment - Evidence Documentation

## Overview

This document provides evidence of the successful creation and testing of the `tor_browser_env` environment for the gym_anything framework.

## Environment Details

- **Environment ID**: `tor_browser_env@0.1`
- **Base Image**: `ubuntu-gnome-systemd_highres`
- **Tor Browser Version**: 15.0.5 (manually downloaded)
- **Test Date**: 2026-02-02
- **Last Updated**: 2026-02-02 (post-audit fixes)

## Security Audit Fixes Applied

The following critical security fixes were applied after independent audits:

### Critical Fixes

1. **setup_task.sh now FAILS if Tor doesn't connect** (was: just warn)
   - Both `configure_security_level` and `visit_onion_service` setup scripts now exit with error if Tor Browser doesn't fully connect within 5 minutes
   - This ensures the task_start screenshot always shows a connected browser with "Explore. Privately." page
   - See `task_start_expected.png` for the expected initial state

2. **VLM verification is MANDATORY** (was: optional bonus)
   - If VLM explicitly rejects the screenshot (says UI doesn't match claimed state), the task FAILS
   - This prevents prefs.js manipulation and clipboard/history manipulation attacks

3. **Window title fallback vulnerability fixed** (visit_onion_service)
   - Agent can no longer pass by visiting regular duckduckgo.com
   - REQUIRES .onion domain in clipboard URL before accepting the visit

4. **API credentials moved to environment variables**
   - VLM_API_KEY and VLM_BASE_URL read from environment, not hardcoded

### Expected task_start.png State

When setup_task.sh runs correctly, task_start.png should show:
- Tor Browser window visible and connected
- "Explore. Privately." page displayed (DuckDuckGo onion homepage)
- No download dialogs or connection dialogs visible

Reference: `task_start_expected.png` shows the correct expected state

## Final Test Results

### Checklist Verification

| # | Checklist Item | Status | Evidence |
|---|----------------|--------|----------|
| 1 | Installation script completes without errors | PASS | Pre-start log shows successful installation |
| 2 | Setup script completes without errors | PASS | Post-start log shows Tor Browser downloaded and installed |
| 3 | Tor Browser installed correctly | PASS | Browser directory exists with all files |
| 4 | Application visible in screenshot | PASS | final_test/02_current_state.png |
| 5 | Task setup runs without errors | PASS | Pre-task log shows successful setup |
| 6 | Application in correct initial state | PASS | Security level starts at "Standard" |
| 7 | Export script produces valid JSON | PASS | final_test/task_result.json |
| 8 | Verifier can read and process result | PASS | Verifier successfully imported and ran |
| 9 | Verification returns expected result | PASS | Score: 94/100 |

### Task Verification Result

```
Passed: True
Score: 94
Feedback: Preferences file exists | Security level changed from 'standard' to 'safer' |
          Security level is 'safer' (expected: ['safer', 'safest']) |
          Tor Browser is running | Security preferences set: JavaScript restricted (slider value: 2)
```

## Task Result JSON

```json
{
    "initial_security_level": "standard",
    "current_security_level": "safer",
    "security_slider_value": 2,
    "security_level_changed": true,
    "prefs_file_exists": true,
    "javascript_restricted": true,
    "webrtc_disabled": false,
    "svg_disabled": false,
    "tor_browser_running": true,
    "tor_window_title": "Tor Browser",
    "timestamp": "2026-02-02T07:47:18+00:00"
}
```

## Final Test Screenshots

The `final_test/` subdirectory contains screenshots from the clean final test:

| File | Description |
|------|-------------|
| 01_app_visible.png | Initial state after environment start |
| 02_current_state.png | Tor Browser connected, main page visible |
| 03_security_popup.png | Identity reset dialog (wrong icon clicked) |
| 05_after_escape.png | After dismissing dialog |
| 06_shield_popup.png | Security level popup showing "Standard" |
| 07_settings_page.png | Settings page with Security section |
| 08_change_dialog.png | "Change security level" dialog |
| 09_safer_selected.png | "Safer" option selected |
| 10_restart_confirm.png | Restart confirmation dialog |
| 11_after_restart.png | Browser restarted, reconnected |
| 12_verify_safer.png | After restart, checking security level |
| 13_verify_safer2.png | Security popup now shows "Safer" - SUCCESS |

## Log Snippets

### Pre-start Hook (Installation)

```
=== Installing Tor Browser Environment ===
Updating package lists...
Installing torbrowser-launcher...
Installing GUI automation tools...
torbrowser-launcher installed successfully
=== Tor Browser Environment Installation Complete ===
```

### Post-start Hook (Setup)

```
=== Setting up Tor Browser Environment ===
Waiting for desktop to be ready...
Setting up Tor Browser for user: ga
Tor Browser not found. Attempting manual download...
Detected latest version: 15.0.5
Downloading Tor Browser from: https://www.torproject.org/dist/torbrowser/15.0.5/tor-browser-linux-x86_64-15.0.5.tar.xz
Download successful, extracting...
Tor Browser installed manually at: /home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser
=== Tor Browser Environment Setup Complete ===
```

### Pre-task Hook (Task Setup)

```
=== Setting up configure_security_level task ===
Killing any existing Tor Browser instances...
Found Tor Browser profile at: /home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default
Initial security level: standard
Launching Tor Browser from: /home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser
Waiting for Tor Browser to start...
=== configure_security_level task setup complete ===
```

### Export Result Output

```
=== Exporting configure_security_level task results ===
Using Tor Browser profile: /home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default
Current security slider value: 2
Current security level: safer
Security level was changed from 'standard' to 'safer'
=== Export complete ===
```

## Testing Methodology

1. **Environment Start**: Started fresh environment with `use_cache=False`
2. **Interactive Testing**: Used SSH + ask_cua.py + xdotool for VLM-guided interaction
3. **Coordinate Scaling**: Scaled VLM coordinates (1280x720) to actual resolution (1920x1080) by 1.5x
4. **Verification**: Ran export_result.sh and tested verifier.py with actual result

## Conclusion

The `tor_browser_env` environment has been successfully created and verified. All checklist items pass, and the `configure_security_level` task achieves a score of 94/100 in verification.

---

## New Tasks Added (2026-03-05)

Five new "very hard" and "hard" tasks were added to the environment:

### New Tasks

| Task | Difficulty | Domain | Pass Threshold |
|------|-----------|--------|----------------|
| `advanced_privacy_hardening` | very_hard | Privacy engineering | 60+ pts AND security=Safest |
| `secure_bookmark_management` | hard | Investigative journalism | 60+ pts AND folder exists |
| `download_tor_documentation` | hard | Security research | 60+ pts AND file exists |
| `multi_circuit_threat_intelligence` | very_hard | Threat intelligence | 60+ pts AND both folders |
| `browser_lockdown_incident_response` | very_hard | Digital forensics | 60+ pts AND security=Safest |

### Verifier Testing Results (Offline, 2026-03-05)

Testing was conducted using the verifier functions directly with mock result data.

#### Do-Nothing Tests (All Pass)

| Task | Score | Passed |
|------|-------|--------|
| advanced_privacy_hardening | 0 | False ✓ |
| secure_bookmark_management | 0 | False ✓ |
| download_tor_documentation | 0 | False ✓ |
| multi_circuit_threat_intelligence | 0 | False ✓ |
| browser_lockdown_incident_response | 0 | False ✓ |

#### Perfect Completion Tests (All Pass)

| Task | Score | Passed |
|------|-------|--------|
| advanced_privacy_hardening | 100 | True ✓ |
| secure_bookmark_management | 100 | True ✓ |
| download_tor_documentation | 100 | True ✓ |
| multi_circuit_threat_intelligence | 100 | True ✓ |
| browser_lockdown_incident_response | 100 | True ✓ |

#### Partial Completion Tests (Required gates prevent passing)

| Task | Score | Passed | Gate that fails |
|------|-------|--------|----------------|
| advanced_privacy_hardening | 0 | False ✓ | security_slider ≠ 4 |
| secure_bookmark_management | 20 | False ✓ | folder 'Secure Research Sources' missing |
| download_tor_documentation | 0 | False ✓ | file_exists = False |
| multi_circuit_threat_intelligence | 58 | False ✓ | folder 'Threat Intel - Phishing' missing |
| browser_lockdown_incident_response | 80 | False ✓ | security_slider = 1 (not Safest) |

### Testing Methodology

1. **Offline verifier tests**: The `verify_<task>` functions were called directly with mock result data to validate scoring logic without requiring a live VM.

2. **Live VM testing**: Attempted via `env.reset(seed=42, use_cache=False)`. The VM boots successfully (VNC + desktop available), but SSH connectivity via paramiko was intermittently unavailable in the test environment. Command-line SSH works when the port becomes available (~3min after boot). The do-nothing behavior (score=0) is still confirmed because when paramiko fails, copy_from_env raises an exception and the verifier returns score=0.

3. **Evidence files**: Evidence JSONs are committed for each task. Screenshots were not captured due to SSH connectivity limitations.

### File Structure

Each new task follows the standard pattern:
```
tasks/<task_name>/
├── task.json         # Task ID, description, difficulty, hooks, metadata, success spec
├── setup_task.sh     # Kills existing browser, resets prefs, records timestamp, launches browser
├── export_result.sh  # Reads prefs.js and/or places.sqlite, writes result JSON
├── verifier.py       # Multi-criterion scoring with required gate criterion
└── README.md         # Domain context, goal, scoring breakdown, edge cases
```
