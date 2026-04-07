# Live Recording Session Prep Task (`live_recording_session_prep@1`)

## Overview

**Occupation:** Audio and Video Technician (SOC 27-4011)
**Industry:** Live Events / Entertainment
**Difficulty:** very_hard
**Estimated time:** 18 minutes

This task simulates a house sound engineer at a jazz club preparing an Ardour session for a multi-track live recording of a jazz quartet. The agent must create 7 input tracks and 2 bus (subgroup) tracks per the band's technical rider, configure stereo pan positions for the piano pair and saxophone, place set list markers for each song in the performance, and set bus gain levels for the drum and piano subgroups.

## Domain Context

Live recording session preparation is a critical pre-show task for audio technicians. Before the musicians arrive, the engineer must configure the DAW session template based on the band's technical rider: create tracks for each input source (individual microphones and DI boxes), set up submix buses for instrument groups (drums, piano stereo pair), configure pan positions to approximate the live stage layout in the stereo image, and place markers for the set list so the recording can be navigated during post-production. Gain staging on bus tracks is set conservatively (typically -6 dB) to provide headroom for the live performance dynamics.

## Goal

The Ardour session should be configured as a complete live recording template with:

- Seven input tracks for the jazz quartet's instruments and room microphones
- Two bus tracks for subgroup mixing (Drum Sub and Piano Sub)
- Pan positions reflecting the stage layout: piano pair panned left/right, saxophone slightly right, others centered
- Seven set list markers placed at the correct positions for each song and the set break
- Bus tracks gain-staged at approximately -6 dB

The band's technical rider with all specifications is at `/home/ga/Audio/gig_info/tech_rider.txt`.

## Success Criteria

| # | Criterion | Points | Description |
|---|-----------|--------|-------------|
| 1 | Seven input tracks | 25 | Seven audio tracks exist with names matching: "Kick Drum", "Drum Overheads", "Upright Bass DI", "Piano Left", "Piano Right", "Tenor Sax", "Room Mics" (flexible alias matching) |
| 2 | Two bus tracks | 15 | Two bus/subgroup tracks exist with names matching: "Drum Sub" and "Piano Sub" (aliases like "drum bus", "piano group" also accepted) |
| 3 | Pan positions | 20 | Three key pan positions approximately correct: Piano Left ~0.15 (35% left), Piano Right ~0.85 (35% right), Tenor Sax ~0.65 (15% right) -- tolerance +/- 0.15 |
| 4 | Set list markers | 20 | At least 5 of 7 markers placed matching set list song titles at correct positions (30-second tolerance): "Autumn Leaves" (0), "Blue in Green" (13230000), "All Blues" (26460000), "Set Break" (39690000), "My Favorite Things" (52920000), "Giant Steps" (66150000), "Take Five" (79380000) |
| 5 | Bus gain | 20 | Both bus tracks have gain between -9 dB and -3 dB (centered on the target of -6 dB) |

**Total:** 100 points
**Pass threshold:** 55/100

## Verification Strategy

The verifier (`verifier.py::verify_live_recording_session_prep`) inspects the Ardour session XML:

1. **Seven input tracks:** Parses all `<Route>` elements (excluding Master/Monitor), and matches each route name against alias lists for each of the 7 required input tracks. For example, "Kick Drum" also matches "kick", "bass drum", or "bd". Partial credit scales with the number found: 7=25pts, 5-6=18pts, 3-4=10pts, 1-2=5pts.

2. **Two bus tracks:** Checks route names against bus aliases (e.g., "drum sub", "drum_sub", "drum bus", "drum group" for Drum Sub). Both buses found earns 15 points; one found earns 8; a bus-like track with a non-matching name earns 3.

3. **Pan positions:** For each of the 3 key tracks (Piano Left, Piano Right, Tenor Sax), reads the `<Controllable>` element containing "pan" in its name and compares the float value against the expected position. Tolerance is +/- 0.15. All other tracks (Kick, Overheads, Bass, Room) are expected at center but are not explicitly checked for this criterion.

4. **Set list markers:** Extracts `<Location>` elements and matches by song title keyword (e.g., "autumn" for "Set 1 - Autumn Leaves"). For the first marker (position 0), accepts anything within 5 seconds. For others, uses a 30-second tolerance (1,323,000 samples). Also recognizes generic set markers ("Set 1", "Set 2", "Set Break", "Encore") as fallback matches.

5. **Bus gain:** For each found bus track, reads the gain controllable value, converts to dB, and checks if it falls within -9 to -3 dB. Both buses correct earns 20 points; one correct earns 10; gain changed but outside range earns 5.

## Schema / Data Reference

**Session file:** `/home/ga/Audio/sessions/MyProject/MyProject.ardour`

**Source material:**
- `/home/ga/Audio/gig_info/tech_rider.txt` -- band technical rider with complete specifications

**Required input tracks:**
| Track | Pan | Notes |
|-------|-----|-------|
| Kick Drum | center (0.50) | Mono |
| Drum Overheads | center (0.50) | Stereo |
| Upright Bass DI | center (0.50) | Mono |
| Piano Left | 35% left (0.15) | Mono |
| Piano Right | 35% right (0.85) | Mono |
| Tenor Sax | 15% right (0.65) | Mono |
| Room Mics | center (0.50) | Stereo |

**Required bus tracks:**
| Bus | Gain | Purpose |
|-----|------|---------|
| Drum Sub | -6 dB | Subgroup for Kick + Overheads |
| Piano Sub | -6 dB | Subgroup for Piano L + Piano R |

**Set list markers (at 44100 Hz sample rate):**
| Song | Sample Position | Time |
|------|-----------------|------|
| Set 1 - Autumn Leaves | 0 | 0:00 |
| Blue in Green | 13,230,000 | 5:00 |
| All Blues | 26,460,000 | 10:00 |
| Set Break | 39,690,000 | 15:00 |
| Set 2 - My Favorite Things | 52,920,000 | 20:00 |
| Giant Steps | 66,150,000 | 25:00 |
| Encore - Take Five | 79,380,000 | 30:00 |

## Edge Cases

- **Bus vs. track distinction:** Ardour treats buses and audio tracks as different route types, but the verifier checks all routes (not just audio tracks) for bus matching. Creating a bus using Ardour's bus creation dialog or simply creating an audio track named "Drum Sub" both count.
- **Center-panned tracks:** Tracks specified as center (0.50) are at Ardour's default pan position, so no active adjustment is needed. Only Piano Left, Piano Right, and Tenor Sax require explicit pan changes.
- **Marker position tolerance for songs:** The 30-second tolerance is generous because the set list positions represent approximate song start times. A marker at 13,200,000 instead of 13,230,000 (off by ~0.7 seconds) easily passes.
- **Generic set markers as fallback:** If song-specific markers are not found, the verifier also accepts "Set 1", "Set 2", "Set Break", and "Encore" as valid markers, though these only contribute if the song-title matching did not already find enough.
- **Bus gain at default (0 dB):** Unity gain does not fall within the -9 to -3 dB acceptance range, so unchanged bus gain scores 0 on this criterion.
- **Marker count capped at 7:** Even if more than 7 markers are matched (e.g., through both song-specific and generic matching), the count is capped at the expected maximum of 7.
- **Do-nothing baseline:** A session with only the default "Audio 1" track scores 0 across all criteria and fails.
