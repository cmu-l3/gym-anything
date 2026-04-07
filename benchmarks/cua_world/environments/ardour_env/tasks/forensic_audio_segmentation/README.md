# Forensic Audio Segmentation Task (`forensic_audio_segmentation@1`)

## Overview

**Occupation:** Forensic Science Technician (SOC 19-4092)
**Industry:** Legal / Criminal Justice
**Difficulty:** very_hard
**Estimated time:** 20 minutes

This task simulates a forensic audio examiner at a county crime lab processing an evidence recording for a criminal case. The agent must label the audio track with the case exhibit identifier, place markers at identified segment boundaries within the recording, export each segment as a separate WAV file, create a chain of custody document with required legal fields, and preserve the original recording intact throughout the process.

## Domain Context

Forensic audio analysis requires meticulous documentation and evidence preservation. When law enforcement submits an audio recording as evidence, the crime lab must segment it into identifiable portions (speakers, background noise, unintelligible sections), export those segments for review by attorneys and the court, and maintain a chain of custody log that documents every action taken. The original evidence must never be destructively edited -- all work is non-destructive. Proper labeling with case numbers and exhibit identifiers is mandatory for admissibility in court proceedings.

## Goal

The Ardour session and export directory should contain:

- The main audio track renamed with the case exhibit identifier ("Exhibit A - Case 2024-CR-0847")
- Markers placed at each of the 6 segment boundaries identified in the evidence intake form
- Five segment WAV files exported to the designated evidence output directory
- A chain of custody text file containing all required legal fields (case number, exhibit ID, lab file number, examiner reference, segment descriptions, and a preservation statement)
- The original audio region preserved intact in the session (not deleted or destructively edited)

The evidence recording and intake form with full instructions are at `/home/ga/Audio/evidence_intake/`.

## Success Criteria

| # | Criterion | Points | Description |
|---|-----------|--------|-------------|
| 1 | Track label | 20 | The audio track name contains a case/exhibit reference: "exhibit", "2024-cr-0847", "0847", "case", or "evidence" (must not be default "Audio 1") |
| 2 | Segment markers | 20 | At least 5 of 6 markers/ranges placed at correct boundary positions within 1.5-second tolerance: 0, 220500, 661500, 793800, 1102500, 1323000 |
| 3 | Five segment exports | 25 | Five WAV files (>100 bytes each) exist in `/home/ga/Audio/evidence_output/` matching expected segment filenames or alternative naming patterns |
| 4 | Chain of custody | 20 | A `chain_of_custody.txt` file exists in the export directory containing at least 4 of 5 required fields: case number, exhibit ID, lab file number, segment descriptions, and a preservation/non-alteration statement |
| 5 | Original preserved | 15 | At least one `<Region>` element still exists in the session XML, confirming the original audio was not deleted |

**Total:** 100 points
**Pass threshold:** 60/100

## Verification Strategy

The verifier (`verifier.py::verify_forensic_audio_segmentation`) checks session XML, exported files, and the chain of custody document:

1. **Track label:** Enumerates audio `<Route>` elements and checks that at least one (not named "Audio 1") contains a case-related keyword: "exhibit", "2024-cr-0847", "0847", "case", or "evidence". A renamed track without case keywords earns 8/20 partial credit.

2. **Segment markers:** Extracts `<Location>` elements, excludes system ranges, and checks both `start` and `end` attributes against each expected boundary sample position (0, 220500, 661500, 793800, 1102500, 1323000) with a 1.5-second tolerance (66150 samples). Both point markers and range markers are accepted.

3. **Five segment exports:** Attempts to copy each expected filename from `/home/ga/Audio/evidence_output/`:
   - `segment_01_background.wav`
   - `segment_02_speaker1_defendant.wav`
   - `segment_03_crosstalk.wav`
   - `segment_04_speaker2_complainant.wav`
   - `segment_05_ambient_tail.wav`

   Falls back to alternative keyword-based filenames (e.g., "seg_01.wav", "background.wav", "defendant.wav").

4. **Chain of custody:** Copies `chain_of_custody.txt` from the export directory, reads its content (case-insensitive), and checks for 5 required fields:
   - Case number: "2024-cr-0847" or "0847"
   - Exhibit ID: "exhibit a"
   - Lab file number: "ae-2024-1547" or "1547"
   - Segment descriptions: "segment", "speaker", "background", or "crosstalk"
   - Preservation statement: "original", "not altered", "unaltered", "preserved", "intact", or "not modified"

5. **Original preserved:** Counts all `<Region>` elements across all playlists in the session XML. At least 1 region must remain, confirming the original audio was not deleted during segmentation.

## Schema / Data Reference

**Session file:** `/home/ga/Audio/sessions/MyProject/MyProject.ardour`

**Source material:**
- `/home/ga/Audio/evidence_intake/exhibit_A_recording.wav` -- original evidence recording (~30 seconds)
- `/home/ga/Audio/evidence_intake/intake_form.txt` -- evidence intake form with case details and segmentation instructions

**Export destination:** `/home/ga/Audio/evidence_output/`

**Case details:**
- Case Number: 2024-CR-0847
- Case Title: State v. Thompson
- Exhibit: Exhibit A
- Lab File #: AE-2024-1547

**Segment boundaries (sample positions at 44100 Hz):**
| Segment | Description | Start | End |
|---------|-------------|-------|-----|
| 1 | Background Noise | 0 | 220500 |
| 2 | Speaker 1 - Defendant | 220500 | 661500 |
| 3 | Unintelligible Crosstalk | 661500 | 793800 |
| 4 | Speaker 2 - Complainant | 793800 | 1102500 |
| 5 | Ambient Noise Tail | 1102500 | 1323000 |

## Edge Cases

- **Range markers vs. point markers:** The verifier accepts both range markers (with distinct start/end) and point markers placed at segment boundaries. Either approach earns credit if positions are within tolerance.
- **Chain of custody with extra content:** Additional text in the chain of custody file does not penalize the score -- the verifier only checks for the presence of required fields.
- **Partial case number:** Including just "0847" in the track name is sufficient for the case keyword match; the full "2024-CR-0847" is not strictly required.
- **Non-destructive editing only:** If the agent deletes the original region (e.g., by using destructive trim operations), the original-preserved criterion scores 0. Standard Ardour operations like splitting regions are non-destructive and preserve the region count.
- **Chain of custody not in expected location:** The verifier only checks `/home/ga/Audio/evidence_output/chain_of_custody.txt`. A file saved elsewhere (e.g., the evidence intake directory) will not be found.
- **Do-nothing baseline:** A session with the default "Audio 1" track and one original region scores only 15/100 (from the preserved-original criterion) and fails.
