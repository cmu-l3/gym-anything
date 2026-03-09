# Navigate Timeline and Capture Specific Intraoperative Window (`navigate_timeline_window@1`)

## Overview
This task requires the agent to navigate Vital Recorder's timeline controls to zoom into a specific time window of a loaded VitalDB surgical case recording and capture a screenshot of that window for a case review presentation.

## Rationale
**Why this task is valuable:**
- Tests timeline navigation skills (zoom in/out, scroll, jump to time)
- Requires understanding of temporal data visualization
- Tests file system interaction (saving output to specific path)

**Real-world Context:** An anesthesiologist needs a snapshot of the patient's vitals during the induction phase (around 20 minutes in) to discuss hemodynamic changes during a morbidity and mortality conference.

## Task Description

**Goal:** Zoom to a ~5-minute window centered at the 20-minute mark of Case #6 and save a screenshot.

**Starting State:**
- Vital Recorder is open with Case #6 loaded.
- The view is zoomed out (showing the full case).

**Expected Actions:**
1. Zoom in until the timeline shows about 5 minutes of data.
2. Scroll to the 20-minute mark (00:20:00).
3. Ensure waveforms are visible.
4. Take a screenshot and save it to `C:\Users\Docker\Desktop\case_review_capture.png`.

**Final State:**
- A PNG file exists at the specified path showing the correct time window.

## Verification Strategy

### Primary Verification: File Analysis
- Checks if the screenshot file exists.
- Checks if the file was created during the task (anti-gaming timestamp check).

### Secondary Verification: VLM Visual Analysis
- **Time Window**: VLM checks if the visible time range on the axis is roughly 3-7 minutes.
- **Time Center**: VLM checks if the time labels are around 00:20:00.
- **Content**: VLM verifies waveforms are visible and the app is Vital Recorder.

### Scoring System
| Criterion | Points |
|-----------|--------|
| File exists and is valid PNG | 15 |
| File created during task | 10 |
| VLM: Zoom level correct (~5 min window) | 25 |
| VLM: Position correct (~20 min mark) | 25 |
| VLM: Vital signs visible | 15 |
| VLM: App UI visible | 10 |
| **Total** | **100** |

Pass Threshold: 60 points