# Audiobook Chapter Mastering Task (`audiobook_chapter_mastering@1`)

## Overview

**Occupation:** Sound Engineering Technician (SOC 27-4014)
**Industry:** Publishing
**Difficulty:** very_hard
**Estimated time:** 18 minutes

This task simulates an audio engineer at a publishing house preparing a raw audiobook narration for ACX (Audible) submission. The agent must segment a single continuous narration recording into three separate chapters, rename the track to reflect the book title, adjust gain levels to meet ACX technical requirements, and export each chapter as an individual WAV file.

## Domain Context

Audiobook production for platforms like ACX/Audible requires strict adherence to technical specifications. Narrators typically deliver recordings as long continuous takes, and engineers must segment them into individual chapter files. Each chapter must meet ACX standards: WAV format at 44.1 kHz, peak levels between -6 dB and -3 dB, with brief room tone at head and tail. Chapter markers in the DAW session serve as reference points for the segmentation process. Proper file naming conventions ensure the distributor can ingest files in the correct order.

## Goal

The Ardour session should contain a properly prepared audiobook with:

- The main audio track renamed to reflect the book title (not the default "Audio 1")
- Chapter markers placed at each chapter boundary (4 markers defining 3 chapter regions)
- Track gain adjusted to meet ACX peak level requirements (-6 dB to -3 dB)
- Three chapter WAV files exported to the designated output directory
- All exported files valid (non-zero, meaningful content)

The raw narration file and chapter plan with exact specifications are at `/home/ga/Audio/audiobook_raw/`.

## Success Criteria

| # | Criterion | Points | Description |
|---|-----------|--------|-------------|
| 1 | Track rename | 15 | The audio track is renamed to contain a relevant keyword ("narration", "strategic", "chapter", "audiobook", or "narrator") and is not the default "Audio 1" |
| 2 | Chapter markers | 25 | 4 markers placed at correct positions within 1.5-second tolerance: Ch1 start (0), Ch2 start (441000), Ch3 start (882000), End (1323000) |
| 3 | Gain (ACX range) | 15 | At least one audio track has gain between -6 dB and -3 dB (ideal ACX range). Wider range of -9 dB to 0 dB earns partial credit. |
| 4 | Three chapter exports | 30 | Three WAV files exist in `/home/ga/Audio/audiobook_export/`, named ch01_introduction.wav, ch02_first_principles.wav, ch03_strategic_framework.wav (alternative naming patterns accepted) |
| 5 | Valid WAV files | 15 | Exported files are valid (file size exceeds 1 KB, indicating actual audio content rather than empty/corrupt files) |

**Total:** 100 points
**Pass threshold:** 60/100

## Verification Strategy

The verifier (`verifier.py::verify_audiobook_chapter_mastering`) checks session XML and exported files:

1. **Track rename:** Enumerates audio `<Route>` elements and checks that at least one has a name (case-insensitive) containing "narration", "strategic", "chapter", "audiobook", or "narrator", and is not "Audio 1". A rename to something unrelated (e.g., "My Track") earns 7/15 partial credit.

2. **Chapter markers:** Extracts `<Location>` elements, filters out system locations, and checks if markers exist within 1.5 seconds (66150 samples) of each expected boundary position: 0, 441000, 882000, and 1323000. The verifier matches by position proximity, not by name.

3. **Gain (ACX range):** Reads `<Controllable name="gaincontrol">` from each audio route, converts linear to dB, and checks if any track's gain falls within -6 to -3 dB. A wider acceptable range (-9 to 0 dB, excluding exactly 0) earns partial credit (8/15).

4. **Three chapter exports:** Attempts to copy files from `/home/ga/Audio/audiobook_export/` using the expected filenames first, then tries alternative naming patterns (e.g., "ch01.wav", "chapter_1.wav", "introduction.wav"). Falls back to checking Ardour's default export directory.

5. **Valid WAV files:** Checks that each found export file exceeds 1 KB in size, confirming it contains actual audio data rather than being an empty or truncated file.

## Schema / Data Reference

**Session file:** `/home/ga/Audio/sessions/MyProject/MyProject.ardour`

**Source material:**
- `/home/ga/Audio/audiobook_raw/narration_full.wav` -- complete narration recording (~30 seconds)
- `/home/ga/Audio/audiobook_raw/chapter_plan.txt` -- full specifications including chapter boundaries and ACX requirements

**Export destination:** `/home/ga/Audio/audiobook_export/`

**Expected export filenames:**
- `ch01_introduction.wav` (samples 0 to 441000)
- `ch02_first_principles.wav` (samples 441000 to 882000)
- `ch03_strategic_framework.wav` (samples 882000 to 1323000)

**Key metadata from task.json:**
- `chapter_boundaries_samples`: [0, 441000, 882000, 1323000]
- `acx_gain_range_db`: [-6, -3]
- `track_name_keywords`: ["narration", "strategic", "chapter", "audiobook"]

**Sample rate:** 44100 Hz

## Edge Cases

- **Default gain passes partially:** If gain is never changed (0 dB), it falls outside both the ideal (-6 to -3) and partial (-9 to 0, excluding 0) ranges, scoring 0 for this criterion. However, the default gain of 0 dB with exact float comparison may be excluded by the `gain_db != 0.0` check.
- **Marker matching by position, not name:** The verifier ignores marker names and only checks positional proximity. Markers named "A", "B", "C", "D" at the correct positions still earn full credit.
- **Export filename flexibility:** The verifier tries multiple naming patterns per chapter (e.g., "ch01", "chapter_1", "chapter1", "introduction"). Completely non-matching names (e.g., "file1.wav") will not be found.
- **Single export instead of three:** Exporting the entire session as one WAV file counts as 1/3 chapters, earning only 10/30 points for criterion 4.
- **Exports to wrong directory:** If files are exported to Ardour's default export location instead of `/home/ga/Audio/audiobook_export/`, the verifier checks there as a fallback.
- **Track rename to book title without keywords:** Renaming to "The Art of Strategic Thinking" matches via the "strategic" keyword and earns full credit.
