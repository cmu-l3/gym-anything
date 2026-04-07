# Film Scoring Session Setup Task (`film_scoring_session_setup@1`)

## Overview

**Occupation:** Music Director / Composer (SOC 27-2041)
**Industry:** Motion Picture & Video Production
**Difficulty:** very_hard
**Estimated time:** 18 minutes

This task simulates a music director preparing an Ardour session template for scoring a short documentary film. The agent must create the required instrument tracks, place scene markers at precise timecodes from the director's spotting notes, configure pan positions for spatial placement of orchestral elements, import reference audio onto a dialogue track, and mute that reference track so it does not bleed into the final score.

## Domain Context

Film scoring session setup is a preparatory step that music directors perform before any composition or recording begins. The session template establishes the track layout, maps scene markers to the picture editor's timecodes, and configures pan positions to approximate the final stereo image. A "Dialogue Ref" track carrying a rough audio mix from the film helps the composer align musical cues to dialogue and scene transitions, but it must be muted to prevent accidental inclusion in the score output. Accurate marker placement at scene boundaries is critical for synchronization.

## Goal

The Ardour session should be configured as a complete film scoring template with:

- Five named instrument/reference tracks matching the spotting notes
- Six scene markers placed at the correct sample positions corresponding to film timecodes
- Pan positions set per the director's specifications (strings left, synth right, others center)
- Reference audio imported onto the Dialogue Ref track at the Interview 1 timecode position
- The Dialogue Ref track muted

The spotting notes with all specifications are at `/home/ga/Audio/film_project/spotting_notes.txt`.

## Success Criteria

| # | Criterion | Points | Description |
|---|-----------|--------|-------------|
| 1 | Track names | 20 | Five audio tracks exist with names matching: "Strings", "Piano", "Ambient Synth", "Percussion", "Dialogue Ref" (flexible alias matching) |
| 2 | Scene markers | 20 | At least 5 of 6 markers placed at correct positions (within 10% tolerance): Opening Titles (0), Interview 1 (1323000), B-Roll Montage (3307500), Interview 2 (5292000), Closing (7938000), End Credits (9261000) |
| 3 | Pan positions | 20 | Pan values approximately correct: Strings ~0.20 (30% left), Piano ~0.50 (center), Ambient Synth ~0.70 (20% right), Percussion ~0.50, Dialogue Ref ~0.50 (tolerance: +/- 0.15) |
| 4 | Reference audio placement | 20 | An audio region exists on the Dialogue Ref track with its position within 15% of sample 1323000 (the Interview 1 timecode) |
| 5 | Dialogue Ref muted | 20 | The Dialogue Ref track has its mute state set to true |

**Total:** 100 points
**Pass threshold:** 60/100

## Verification Strategy

The verifier (`verifier.py::verify_film_scoring_session_setup`) inspects only the Ardour session XML:

1. **Track names:** Parses `<Route>` elements, excludes Master/Monitor, and matches each route name against alias lists for the 5 required tracks (e.g., "ambient synth", "ambient_synth", "synth", "ambient" all match the Ambient Synth requirement).

2. **Scene markers:** Extracts `<Location>` elements (excluding system ranges), matches marker names by keyword presence (e.g., a marker name containing "interview" and near position 1323000 matches "Interview 1"). For position 0, accepts any marker within 1 second (44100 samples). For other positions, uses 10% relative tolerance.

3. **Pan positions:** For each found track, reads the `<Controllable>` element whose name contains "pan" and compares its float value against the expected pan position. Tolerance is +/- 0.15 on the 0.0-1.0 scale.

4. **Reference audio placement:** Finds the Dialogue Ref route, locates its playlist's `<Region>` elements, and checks if any region's position is within 15% of sample 1323000.

5. **Mute state:** Checks the Dialogue Ref route for a `<Controllable name="mute">` with value "1" (or "yes"/"true"), or a `muted="1"` attribute on the `<Route>` element itself.

## Schema / Data Reference

**Session file:** `/home/ga/Audio/sessions/MyProject/MyProject.ardour`

**Source material:**
- `/home/ga/Audio/film_project/spotting_notes.txt` -- director's spotting notes with all specifications
- `/home/ga/Audio/samples/moonlight_sonata.wav` -- reference audio to import onto Dialogue Ref

**Key metadata from task.json:**
- `required_tracks`: ["Strings", "Piano", "Ambient Synth", "Percussion", "Dialogue Ref"]
- `scene_markers`: Opening Titles (0), Interview 1 (1323000), B-Roll Montage (3307500), Interview 2 (5292000), Closing (7938000), End Credits (9261000)
- `pan_positions`: Strings 0.20, Piano 0.50, Ambient Synth 0.70, Percussion 0.50, Dialogue Ref 0.50
- `ref_audio_position`: 1323000 (sample offset for Interview 1)

**Sample rate:** 44100 Hz

## Edge Cases

- **Pan at default center:** Tracks specified as center (0.50) will pass even if pan is never explicitly changed, since Ardour defaults to center. Only Strings (0.20) and Ambient Synth (0.70) truly require active adjustment.
- **Marker name partial matching:** The verifier matches by keyword within the marker name, so "Interview 1 - Maria speaks" would match the "Interview 1" expectation. However, a generic name like "Marker 2" would not match.
- **Position tolerance:** The 10% relative tolerance means Interview 1 at sample 1323000 accepts positions from ~1,190,700 to ~1,455,300. The tolerance for the Opening Titles marker (position 0) is an absolute 1-second window (0 to 44100).
- **Mute without Dialogue Ref track:** If the Dialogue Ref track does not exist at all, the mute criterion scores 0 (the verifier checks for the track first, then its mute state).
- **Audio on wrong track:** If reference audio is imported but placed on a track other than Dialogue Ref, partial credit (3 points) is awarded.
- **Do-nothing baseline:** A session with only the default "Audio 1" track scores 0 across all criteria.
