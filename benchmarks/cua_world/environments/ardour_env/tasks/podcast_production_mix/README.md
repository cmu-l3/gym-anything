# Podcast Production Mix Task (`podcast_production_mix@1`)

## Overview

**Occupation:** Broadcast Technician (SOC 27-4012)
**Industry:** Broadcasting / Media
**Difficulty:** very_hard
**Estimated time:** 15 minutes

This task simulates a broadcast technician assembling a podcast episode from raw audio files in a DAW. The agent works at WKRP community radio station and must take three separate audio files (intro music, recorded interview, and outro music), arrange them into a coherent episode in Ardour, apply appropriate gain staging for broadcast standards, mark episode segments, and export the final stereo mix.

## Domain Context

Podcast production is a core workflow for broadcast technicians. A typical episode assembly involves importing individual audio segments onto separate tracks, ordering them chronologically, setting gain levels so that music beds sit below spoken content, adding session markers for navigation and editing reference, and bouncing the final mix to a delivery-ready WAV file. The distinction between music gain (reduced) and speech gain (unity) is a fundamental broadcast mixing convention.

## Goal

The Ardour session should contain a fully assembled podcast episode with:

- Three named audio tracks, each holding its respective audio segment
- Audio regions placed in the correct temporal order (intro, then interview, then outro)
- Gain levels appropriate for broadcast: music tracks attenuated, speech at unity
- Session markers identifying the major episode segments
- A final stereo WAV mix exported to the designated delivery directory

The source audio files and a production brief with exact specifications are located at `/home/ga/Audio/podcast_raw/`.

## Success Criteria

| # | Criterion | Points | Description |
|---|-----------|--------|-------------|
| 1 | Track names | 20 | Three audio tracks exist with names matching the spec: "Intro Theme", "Interview", "Outro Theme" (flexible matching with aliases) |
| 2 | Region order | 25 | Audio regions are placed in correct temporal order: intro first (earliest position), interview second, outro third |
| 3 | Gain levels | 20 | Music tracks (Intro Theme, Outro Theme) have gain between -18 dB and -3 dB; speech track (Interview) has gain between -3 dB and +3 dB |
| 4 | Markers | 15 | At least 4 meaningful session markers placed (e.g., "Episode Start", "Interview Begin", "Outro Begin", "Episode End") |
| 5 | Exported WAV | 20 | A WAV file larger than 1 KB exists in `/home/ga/Audio/podcast_final/` |

**Total:** 100 points
**Pass threshold:** 65/100

## Verification Strategy

The verifier (`verifier.py::verify_podcast_production_mix`) operates entirely on artifacts -- no UI inspection is required:

1. **Track names:** Parses the Ardour session XML (`MyProject.ardour`), enumerates audio `<Route>` elements (excluding Master/Monitor buses), and checks each route name against a list of acceptable aliases for each required track (e.g., "intro theme", "intro_theme", "intro music").

2. **Region order:** For each found track, locates its associated `<Playlist>` and extracts `<Region>` elements. Compares the earliest region position across the three tracks to confirm intro < interview < outro ordering.

3. **Gain levels:** Reads the `<Controllable name="gaincontrol">` value from each route, converts from linear to dB (`20 * log10(value)`), and checks against the specified ranges for music vs. speech tracks.

4. **Markers:** Iterates `<Location>` elements, filters out system locations (session range, loop, punch), and counts markers with names longer than 1 character. Requires at least 4 for full credit.

5. **Exported WAV:** Attempts to copy files from `/home/ga/Audio/podcast_final/` using a list of common filenames (community_voices.wav, podcast.wav, mix.wav, etc.). Falls back to checking the default Ardour export directory (`sessions/MyProject/export/`) for partial credit.

## Schema / Data Reference

**Session file:** `/home/ga/Audio/sessions/MyProject/MyProject.ardour` (Ardour XML format)

**Source audio:**
- `/home/ga/Audio/podcast_raw/intro_theme.wav` -- station intro music (~8 seconds)
- `/home/ga/Audio/podcast_raw/interview_segment.wav` -- recorded interview (~20 seconds)
- `/home/ga/Audio/podcast_raw/outro_theme.wav` -- closing music (~8 seconds)
- `/home/ga/Audio/podcast_raw/production_brief.txt` -- full specifications

**Export destination:** `/home/ga/Audio/podcast_final/`

**Key metadata from task.json:**
- `required_tracks`: ["Intro Theme", "Interview", "Outro Theme"]
- `music_gain_db_range`: [-18, -6]
- `speech_gain_db_range`: [-3, 3]
- `required_markers`: ["Episode Start", "Interview Begin", "Outro Begin", "Episode End"]

## Edge Cases

- **Track name variations:** The verifier accepts aliases (e.g., "intro" matches "Intro Theme"). However, completely unrelated names like "Track 1" receive only minimal partial credit.
- **Gain at exact boundary:** A music track at exactly -3 dB or a speech track at exactly +3 dB is accepted (inclusive range comparison).
- **Export to wrong directory:** If the WAV is exported to Ardour's default export location instead of `/home/ga/Audio/podcast_final/`, partial credit (12 points) is awarded instead of the full 20.
- **Single region per track vs. multiple:** The verifier uses the earliest region position per track for ordering, so multiple regions on one track do not cause issues.
- **Default gain (0 dB):** If no gain adjustments are made, the speech track may still pass (0 dB is within -3 to +3), but music tracks at 0 dB will fail their criterion.
- **Do-nothing baseline:** A clean session with only the default "Audio 1" track scores 0 on all criteria and fails.
