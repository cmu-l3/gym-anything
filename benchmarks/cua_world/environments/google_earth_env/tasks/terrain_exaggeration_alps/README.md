# Terrain Exaggeration Alps Visualization (`terrain_exaggeration_alps@1`)

## Overview
This task requires the agent to configure Google Earth Pro's terrain elevation exaggeration setting and create a dramatic 3D visualization of the Matterhorn in the Swiss Alps. The agent must navigate to the settings, adjust the exaggeration multiplier to a specific value, navigate to the mountain, tilt the view to show 3D terrain, and capture a screenshot demonstrating the enhanced vertical relief.

## Rationale
**Why this task is valuable:**
- Tests knowledge of application settings/preferences dialogs
- Requires understanding of 3D view manipulation (tilt, heading)
- Validates numerical parameter configuration
- Tests multi-step workflow involving settings AND navigation
- Verifiable through both config file inspection and visual analysis

**Real-world Context:** A geology professor is preparing lecture materials about Alpine orogeny and mountain formation processes. They need to create a visually striking 3D representation of the Matterhorn that emphasizes the dramatic elevation differences, making it easier for students to understand tectonic uplift and erosion patterns.

## Task Description

**Goal:** Configure Google Earth Pro's terrain elevation exaggeration to 2.5x and capture a tilted 3D view of the Matterhorn (Switzerland) that dramatically displays the exaggerated mountain terrain.

**Starting State:** 
- Google Earth Pro is open and maximized
- View is at default location (likely overview of Earth or last session location)
- Terrain elevation exaggeration is set to default (1.0x)
- 3D view is in top-down (nadir) perspective

**Expected Actions:**
1. Access the Options/Preferences dialog (Tools > Options)
2. Navigate to the 3D View tab
3. Locate the "Elevation Exaggeration" slider/input
4. Set the elevation exaggeration to exactly 2.5
5. Apply and close the settings dialog
6. Navigate to the Matterhorn, Switzerland (search or use coordinates: 45.9766° N, 7.6586° E)
7. Tilt the view to show the mountain in 3D perspective (not top-down)
8. Adjust heading/rotation to show the iconic north face of the Matterhorn
9. Save a screenshot to `/home/ga/matterhorn_exaggerated.png`

**Final State:** 
- Elevation exaggeration setting is 2.5x
- View shows Matterhorn with dramatically exaggerated vertical relief
- 3D tilted perspective clearly visible
- Screenshot saved at specified location

## Verification Strategy

### Primary Verification: Configuration File Analysis
Google Earth Pro stores settings in configuration files. The verifier will:
1. Parse config files in `~/.config/Google/` or `~/.googleearth/`
2. Extract the elevation exaggeration value
3. Verify it equals 2.5 (with tolerance ±0.2)

### Secondary Verification: File Existence and Timestamp
- Check screenshot file exists at expected path
- Verify file size is reasonable (>100KB for a real screenshot)
- Check file was created DURING task execution (anti-gaming)

### Tertiary Verification: VLM Trajectory Analysis
The verifier uses trajectory frames (not just final screenshot) to verify:
- Settings dialog was opened during workflow
- Mountain terrain is visible in final view
- View is tilted showing 3D perspective
- Location appears to be Matterhorn/Swiss Alps region

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| Elevation exaggeration set to 2.5 | 30 | Config file shows correct value (±0.2 tolerance) |
| Screenshot file exists | 15 | File at correct path, reasonable size |
| File created during task | 10 | Timestamp check for anti-gaming |
| VLM: Mountain terrain visible | 15 | Dramatic peaks visible in screenshot |
| VLM: Tilted 3D view | 15 | Not top-down, shows horizon/perspective |
| VLM: Matterhorn/Alps location | 10 | Correct geographic region |
| VLM: Exaggeration evident | 5 | Terrain appears dramatically steep |
| **Total** | **100** | |

**Pass Threshold:** 60 points with at least one key criterion met (config correct OR file created + VLM passes)

## Anti-Gaming Measures

1. **"Do Nothing" Detection**: Initial elevation exaggeration is reset to 1.0 in setup; any pre-existing screenshot is deleted
2. **Timestamp Verification**: File modification time must be after task start time
3. **Trajectory Analysis**: VLM analyzes multiple frames across the workflow to verify actual work was done
4. **Multiple Signals**: Pass requires either config verification OR (file creation + visual verification)

## Data Requirements

**Geographic Data:**
- Matterhorn coordinates: 45.9766° N, 7.6586° E (real coordinates)
- Google Earth's built-in satellite imagery and terrain data

**Initial Configuration:**
- Elevation exaggeration reset to 1.0 in setup_task.sh
- This ensures the task requires actually changing the setting

## Difficulty Analysis

**Estimated Steps:** 12-20 discrete actions
- Menu navigation for settings
- Slider adjustment
- Search/navigation
- View manipulation
- Screenshot save

**Difficulty:** Medium - requires knowledge of settings location and 3D view manipulation