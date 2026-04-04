# Add Parameter Tracks to Waveform Display (`add_parameter_tracks@1`)

## Overview
This task tests the agent's ability to customize the waveform display in Vital Recorder by finding and adding specific physiological parameters from a loaded surgical dataset.

## Rationale
**Why this task is valuable:**
- **Data Navigation:** Real medical datasets contain hundreds of parameters; finding specific ones (like Mean Arterial Pressure vs. Systolic) is a key skill.
- **UI Interaction:** Requires navigating complex tree-based menus or dialogs.
- **Clinical Relevance:** Configuring the monitor view is the first step in any retrospective analysis of surgical vital signs.

**Real-world Context:** An anesthesiologist reviewing a case needs to see specific hemodynamic (blood pressure) and respiratory (CO2) metrics that aren't in the default view to understand a patient's stability during surgery.

## Task Description

**Goal:** Add ART_MBP, ETCO2, and BIS tracks to the Vital Recorder display.

**Starting State:** 
- Vital Recorder is open.
- Case `0001.vital` (from VitalDB) is loaded.
- Only default tracks (e.g., ECG) are visible.

**Expected Actions:**
1. Open the "Add Track" menu or dialog.
2. Locate `Solar8000` device -> `ART_MBP` parameter and add it.
3. Locate `Primus` device -> `ETCO2` parameter and add it.
4. Locate `BIS` device -> `BIS` parameter and add it.
5. Ensure all three tracks are visible in the waveform area.

**Final State:**
- The waveform window displays the three new tracks populated with data.

## Verification Strategy

### Primary Verification: VLM Visual Analysis
The verifier uses a Vision-Language Model (VLM) to analyze the final screenshot. It checks for:
1. Presence of track labels matching "ART_MBP", "ETCO2", and "BIS".
2. Presence of data curves/waveforms (not empty tracks).

### Secondary Verification: Application State
- Checks that the window title indicates the correct file (`0001.vital`) is still loaded.
- Verifies the application is running and maximized.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| **ART_MBP Visible** | 25 | Label 'ART_MBP' found in display |
| **ETCO2 Visible** | 25 | Label 'ETCO2' found in display |
| **BIS Visible** | 25 | Label 'BIS' found in display |
| **Data Loaded** | 15 | Waveforms are not flat/empty |
| **Correct File** | 10 | Window title matches '0001.vital' |
| **Total** | **100** | |

Pass Threshold: 60 points (Must have at least 2/3 tracks visible).