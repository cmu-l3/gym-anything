# Fleet Dashcam PiP Synchronization (`fleet_dashcam_pip_synchronization@1`)

## Overview
This task evaluates the agent's ability to analyze multi-angle video footage, identify a specific synchronization event (via visual and audio cues), calculate time offsets, and execute a complex media filtergraph to produce a synchronized Picture-in-Picture (PiP) composite video trimmed to a precise temporal window.

## Rationale
**Why this task is valuable:**
- Tests precise timeline synchronization across multiple independent media files.
- Evaluates sub-second video trimming and temporal offset calculation.
- Requires complex spatial composition (scaling, Picture-in-Picture positioning, and margins).
- Tests selective audio stream mapping and discarding.
- Mirrors a highly common real-world workflow (insurance reporting, security analysis, vlogging).

**Real-world Context:** A logistics company's safety officer needs to submit a synchronized incident video to their insurance provider. The delivery truck's forward-facing and driver-facing dashcams record to separate SD cards and start recording at different times. The officer must manually review the footage, find the exact moment of collision in both files, and generate a synchronized Picture-in-Picture composite video covering just the 15-second incident window.

## Task Description

**Goal:** Find the exact timestamp of an incident in two unsynchronized dashcam videos, calculate their offset, and generate a synchronized Picture-in-Picture composite video covering a precise 15-second window around the incident.

**Starting State:** 
The following files are available in `/home/ga/Videos/`:
- `front_camera.mp4` (1920x1080, no audio or silent audio track)
- `cabin_camera.mp4` (1280x720, includes driver audio track)

*Note: For the purpose of this simulation, the "incident" (collision) has been marked in both videos by a sudden, full-screen solid color flash lasting 0.5 seconds, accompanied by a loud 1000Hz audio beep. The cameras started recording at different times, so this event occurs at different timestamps in each file.*

**Expected Actions:**
1. Inspect both videos (using VLC or CLI analysis tools) to find the exact timestamp of the incident flash.
2. Calculate the temporal offset required to synchronize the two angles.
3. Generate a composite video at `/home/ga/Videos/incident_composite.mp4` matching these specifications exactly:
   - **Resolution:** `1920x1080`
   - **Background:** The `front_camera` footage must fill the screen.
   - **Picture-in-Picture:** The `cabin_camera` footage must be scaled down to exactly `640x360` and overlaid in the bottom-right corner.
   - **Margins:** The PiP overlay must be offset exactly `20` pixels from the right edge and `20` pixels from the bottom edge.
   - **Synchronization:** The video must be synced so the incident flash occurs at the *exact same frame* in both the main view and the PiP view.
   - **Trimming:** The final video must start exactly **5.0 seconds BEFORE** the synchronized flash, and end exactly **10.0 seconds AFTER** the flash (Total duration: 15.0 seconds).
   - **Audio:** The output video must contain ONLY the audio track from the `cabin_camera` (discard front audio).

**Final State:** 
A single `incident_composite.mp4` file exists in the Videos directory perfectly meeting all spatial and temporal specifications.

## Verification Strategy

### Primary Verification: Programmatic Frame Extraction & Color Analysis
The task setup generates the files using real driving footage, but injects a **Red** flash into the front camera and a **Blue** flash into the cabin camera. The verifier performs strict mathematical checks on the output video:
- Extracts the frame at `t=5.1s`. Since the output must start exactly 5.0 seconds before the flash, `t=5.1` MUST be during the flash.
- Samples pixel `(600, 500)` (Main area) -> Verifies it is Red (proving front sync and trim).
- Samples pixel `(1580, 880)` (Center of PiP area) -> Verifies it is Blue (proving cabin sync, trim, and correct PiP scaling/general placement).
- Samples pixel `(1910, 880)` (Right margin) -> Verifies it is Red. Since this is 10px from the right edge, it proves the agent correctly applied the 20px right margin (otherwise it would be Blue).
- Samples pixel `(1580, 1070)` (Bottom margin) -> Verifies it is Red, proving the 20px bottom margin.
- Extracts frame at `t=4.0s` -> Verifies neither sampled area is Red or Blue, proving the flash hasn't happened yet.

### Secondary Verification: Metadata & Stream Analysis
- `ffprobe` is used to verify the file exists, has a resolution of 1920x1080, and a duration of ~15.0 seconds (tolerance ±0.2s).
- Verifies that exactly one audio stream exists and matches the codec/channels of the cabin camera source.
- Validates the VLM trajectory to ensure tools were used to construct the output.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| File Integrity | 10 | `incident_composite.mp4` exists with valid video/audio streams. |
| Resolution & Duration | 15 | Video is 1920x1080 and approximately 15.0 seconds long. |
| Audio Mapping | 15 | Audio stream is correctly mapped exclusively from the cabin camera. |
| Temporal Sync & Trim | 30 | Both videos flash at exactly `t=5.0s` in the output timeline. |
| Spatial Composition | 15 | PiP is correctly scaled to 640x360 and respects the 20px bottom/right margins. |
| VLM Verification | 15 | Agent trajectory shows meaningful workflow and execution. |
| **Total** | **100** | |

Pass Threshold: 70 points, with Temporal Sync & Trim met.