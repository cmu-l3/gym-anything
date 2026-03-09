# WPS Office Writer Environment - Testing Evidence

This document provides evidence of environment setup and testing status.

**Last Updated**: 2026-02-03

## Environment Details

- **Environment ID**: `wps_office_writer_env@0.1`
- **Base Image**: `ubuntu-gnome-systemd_highres`
- **WPS Office Version**: 11.1.0.11723
- **Resources**: 4 CPU, 4GB RAM, Network enabled

## Data Sources (REAL DATA - Not Mock/Synthetic)

### format_business_letter Task
- **Recipient Company**: Microsoft Corporation
- **Recipient Address**: One Microsoft Way, Redmond, WA 98052
- **Data Source**: [Microsoft Office Locations](https://www.microsoft.com/en-us/about/office-locations)
- **Recipient Name**: Kathleen Hogan (Microsoft Chief People Officer)

### create_data_table Task
- **Data Source**: [Amazon Q4 2023 Earnings Report](https://ir.aboutamazon.com/news-release/news-release-details/2024/Amazon.com-Announces-Fourth-Quarter-Results/)
- **Regional Data**:
  - North America: $105.5B (+13% YoY) - 62% of total
  - International: $40.2B (+17% YoY) - 24% of total
  - AWS: $24.2B (+13% YoY) - 14% of total
  - Total Q4 2023: $170.0B (+14% YoY)

## Testing Status

### Installation (pre_start hook)
- [x] WPS Office package downloads successfully (318MB)
- [x] Dependencies installed (fonts, Qt libs, automation tools)
- [x] WPS binaries available at `/usr/bin/wps`
- [x] Installation log shows no errors

### Setup (post_start hook)
- [x] User configuration created at `/home/ga/.kingsoft/`
- [x] Desktop shortcuts created
- [x] Launch scripts work correctly
- [x] EULA dialog dismissed using verified coordinates (645, 648) for checkbox, (1266, 648) for confirm button

### Task Start State
- [x] WPS Writer launches successfully
- [x] format_business_letter: draft_letter.docx opens with document content visible
- [x] create_data_table: new_report.docx (blank document) opens ready for editing
- [x] Task start screenshots (frame_00000.png) show WPS Writer with document visible, no dialogs
- [x] EULA dialog handling works reliably with verified coordinates

## Verifier Criteria

### format_business_letter Verifier (9 criteria)
1. **Sender address** - Checks for Emily Chen + Seattle/address
2. **Date** - Requires full date (January 15, 2024), not just "2024"
3. **Recipient address** - Requires specific info (Kathleen Hogan, Redmond, etc.)
4. **Salutation bold** - Checks "Dear Ms. Hogan:" is bold
5. **Body justified** - Checks paragraph alignment
6. **Single line spacing** - NEW: Checks paragraph spacing
7. **Closing italic** - Checks "Sincerely," is italic
8. **Signature line** - NEW: Checks sender name appears after closing
9. **VLM verification** - Visual confirmation (optional if unavailable)

**NOTE**: Content preservation is now a PREREQUISITE, not a scored criterion.
If document content is corrupted, score is 0 (prevents partial credit for doing nothing).

### create_data_table Verifier (10 criteria)
1. **Title present** - Requires "Amazon" + sales/report context
2. **Table exists** - Document contains a table
3. **Dimensions** - Table is 5x4 or larger
4. **Headers** - At least 3 of 4 expected headers found
5. **Data content** - At least 3 rows have expected data
6. **Numeric data** - At least 6 percentage values
7. **Header formatting** - Bold and/or shading on header row
8. **Right-alignment** - NEW: Numeric columns are right-aligned
9. **Alternating colors** - NEW: Row shading/alternating colors
10. **VLM verification** - Visual confirmation (optional if unavailable)

## Known Issues and Fixes

### Issue 1: EULA Dialog Handling
**Status**: Resolved
- EULA dialog appears on first launch but is now dismissed reliably
- Verified coordinates from ask_cua.py testing: checkbox (645, 648), confirm button (1266, 648) in 1920x1080
- Fallback to keyboard navigation (Tab + Space + Enter)
- Multiple detection patterns: "License Agreement", "Kingsoft", "End User License", "EULA"

### Issue 2: Dialog Dismissal
**Status**: Resolved
- "System Check" and "WPS Office default" dialogs dismissed in setup script
- Multiple dismiss attempts with varying coordinates
- Escape key fallback for stubborn dialogs

### Issue 3: Verifier Scoring Vulnerability
**Status**: Fixed
- Previously: "Content preserved" gave 14% score for doing nothing
- Now: Content preservation is a prerequisite - if content is corrupted, score is 0
- Added missing checks: line spacing, signature line, right-alignment, alternating colors

### Issue 4: Export Script Vulnerability
**Status**: Fixed
- Previously: Wildcard `find` could accept any .docx file modified in last 10 minutes
- Now: Only accepts documents at expected paths with expected filenames

## Testing Instructions

To run a test of the environment:

```python
from gym_anything import from_config

# Load environment with task
env = from_config('benchmarks/environments/wps_office_writer_env', task_id='format_business_letter')

# Reset starts the VM and runs setup
obs = env.reset()

# Check frame_00000.png in episode directory for task start state
print(f"Episode: {env._episode_dir}")

# Close when done
env.close()
```

## Artifact Locations

After running a task, artifacts are saved to:
- `benchmarks/environments/wps_office_writer_env/artifacts/episode_YYYYMMDD_HHMMSS_<uuid>/`
  - `frame_00000.png` - Initial task state screenshot
  - `frame_XXXXX.png` - Step screenshots
  - `final.png` - Final state screenshot
  - `summary.json` - Verification results
  - `traj.jsonl` - Action trajectory

## Conclusion

The WPS Office Writer environment:
- Uses REAL data from Microsoft and Amazon official sources
- Has robust verification with 9-10 criteria per task
- Includes prerequisite checks to prevent gaming the verifier
- Handles first-run dialogs (EULA, System Check, etc.)
- Supports resolution-independent coordinate handling

**Verified**: EULA dialog handling works reliably using coordinates discovered via `ask_cua.py` testing. Both tasks now show document content (not EULA or home screen) in frame_00000.png.
