# Theatrical Soundscape Design (`theatrical_soundscape_design@1`)

## Overview

**Occupation:** Sound Designer / Audio and Video Technician (SOC 27-1014 / 27-4011)
**Industry:** Performing Arts Companies (NAICS 7111)
**Difficulty:** hard
**Estimated time:** 15 minutes

This task simulates a theatrical sound designer preparing a spatial audio soundscape for the opening scene of a stage play. The agent must assemble multiple audio files into a multi-track DAW session, configure precise spatial panning (Left, Right, Center), adjust track gains to simulate distance/depth, place audio regions at specific temporal offsets to match stage cues, apply a smooth region fade-in, and document the cues using session markers.

## Rationale

**Why this task is valuable:**
- **Spatial Audio Routing:** Tests the agent's ability to manipulate the stereo field using track pan controls.
- **Gain Staging for Depth:** Requires setting precise relative dB levels to create a sense of foreground and background elements.
- **Temporal Arranging:** Tests precise timeline positioning by forcing the agent to move audio regions to specific second/sample offsets.
- **Region Modification:** Validates the ability to apply non-destructive fade-ins to specific audio regions.
- **Real-world relevance:** Sound designers constantly rely on pan, volume, and timing to create immersive environments for theater, film, and virtual reality.

**Real-world Context:** A sound designer is setting up the opening audio cue sequence for a play. When the curtain rises, the audience should hear a distant piano playing from center stage. Two seconds later, an actor's inner monologue whispers from the left speaker array. Five seconds into the scene, a sudden greeting interrupts from the right speaker array. The designer must build this sequence in Ardour so it can be played back reliably during the show.

## Task Description

**Goal:** Assemble a 3-track theatrical soundscape in Ardour by importing audio samples, staggering their start times (0.0s, 2.0s, 5.0s), panning them for spatial separation (Center, Left, Right), scaling their gains for depth (-12dB, -6dB, 0dB), and adding a fade-in and markers.

**Starting State:** Ardour is open with an empty or default session named "MyProject". The required raw audio files are located in `/home/ga/Audio/samples/` (`moonlight_sonata.wav`, `narration.wav`, `good_morning.wav`).

**Expected Actions:**
1. Create three audio tracks named exactly: **"Piano_Atmos"**, **"Left_Monologue"**, and **"Right_Interruption"**.
2. Import `/home/ga/Audio/samples/moonlight_sonata.wav` onto the "Piano_Atmos" track, positioned at the start of the session (**0.0 seconds**).
3. Import a voice sample (e.g., `/home/ga/Audio/samples/narration.wav`) onto the "Left_Monologue" track, and slide the audio region so it starts exactly at **2.0 seconds**.
4. Import a different voice sample (e.g., `/home/ga/Audio/samples/good_morning.wav` or another copy of narration) onto the "Right_Interruption" track, and slide the region so it starts exactly at **5.0 seconds**.
5. Configure the track panning for spatial separation:
   - Pan "Left_Monologue" **100% Left**.
   - Pan "Right_Interruption" **100% Right**.
   - Leave "Piano_Atmos" panned **Center**.
6. Configure track fader gains to create simulated depth:
   - Set "Piano_Atmos" to **-12 dB**.
   - Set "Left_Monologue" to **-6 dB**.
   - Set "Right_Interruption" to **0 dB** (unity gain).
7. Apply a fade-in of at least **2.0 seconds** to the audio region on the "Piano_Atmos" track so the music swells in smoothly.
8. Create three session location markers at the corresponding cue events: **"Scene Start"** (at 0.0s), **"Monologue"** (at 2.0s), and **"Interruption"** (at 5.0s).
9. Save the session (Ctrl+S).

**Final State:** The Ardour session file is saved with three configured tracks containing properly positioned regions, pans, gains, fades, and markers.

## Verification Strategy

### Primary Verification: Session XML State Inspection
The verifier (`verifier.py::verify_theatrical_soundscape`) parses the `/home/ga/Audio/sessions/MyProject/MyProject.ardour` XML file to objectively measure all parameters:

1. **Track Existence & Naming:** Checks for `<Route>` elements matching the required names (case-insensitive, underscores/spaces interchangeable).
2. **Temporal Alignment:** Locates the `<Playlist>` and `<Region>` for each track. Reads the `position` attribute (stored in audio samples) and verifies the timestamps:
   - Piano: ~0 samples (0.0s)
   - Left_Monologue: ~88,200 samples (2.0s at 44.1kHz)
   - Right_Interruption: ~220,500 samples (5.0s at 44.1kHz)
   *(Accepts a ±0.5 second tolerance).*
3. **Spatial Panning:** Reads the `<Controllable name="pan-azimuth">` value for each route. Verifies Left is < 0.1, Right is > 0.9, and Center is between 0.4 and 0.6.
4. **Gain Staging:** Reads the `<Controllable name="gaincontrol">` linear value. Converts to dB (`20 * log10(val)`) and checks against targets (-12, -6, 0) with a ±2 dB tolerance.
5. **Fades & Markers:** Checks the "Piano_Atmos" `<Region>` for `fade-in-active="1"` and a `fade-in-length` ≥ 80,000 samples. Scans `<Location>` elements for markers near 0, 88200, and 220500 samples.

### Secondary Verification: Artifact & "Do Nothing" Detection
- Checks the file modification timestamp of `MyProject.ardour` to ensure the agent actively saved changes.
- Ensures the default "Audio 1" track (if left untouched) does not accidentally pass the checks.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| Track Setup & Naming | 15 | Three tracks exist matching the requested names (5 pts per track) |
| Temporal Arrangement | 25 | Regions are placed at 0.0s, 2.0s, and 5.0s within ±0.5s tolerance |
| Spatial Panning | 20 | Azimuth values confirm Hard Left, Center, and Hard Right panning |
| Depth Gain Staging | 20 | Track faders are set to -12dB, -6dB, and 0dB within ±2dB tolerance |
| Fade-in & Markers | 20 | 2.0s+ fade-in applied to Piano, and 3 temporal markers placed |
| **Total** | **100** | |

**Pass Threshold:** 60 points with at least partial credit in Temporal Arrangement and Spatial Panning.