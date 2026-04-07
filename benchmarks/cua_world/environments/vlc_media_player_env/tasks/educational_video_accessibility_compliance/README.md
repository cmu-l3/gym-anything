# Educational Video Accessibility Compliance

## Difficulty
Very Hard

## Skills Tested
- SRT subtitle file creation with proper timing
- Subtitle burning (hardcoding into video frames)
- Video resolution downscaling
- Timed screenshot capture
- JSON manifest generation
- Accessibility standards interpretation
- Multi-deliverable pipeline management

## Objective
Prepare a lecture recording for accessible online distribution by creating closed captions, a hardsubbed copy, a low-bandwidth version, section thumbnails, and a deliverables manifest — all meeting Section 508 compliance requirements.

## Real-World Scenario
An instructional designer at a university must make a recorded lecture accessible to all students, including those with disabilities, limited internet access, or mobile-only devices. Section 508 mandates closed captions, and the university's LMS requires multiple video versions and visual navigation aids.

## Task Description
- **Lecture video**: `/home/ga/Videos/lecture_recording.mp4` (90s, 1920x1080, 4 distinct visual sections)
- **Transcript**: `/home/ga/Documents/lecture_transcript.txt` (dialogue with timestamps and section markers)
- **Requirements**: `/home/ga/Documents/accessibility_spec.txt`

### Video Sections:
1. **Introduction to Data Science** (0:00–0:22) — Blue background
2. **Core Statistical Concepts** (0:22–0:45) — Green background
3. **Real-World Applications** (0:45–1:08) — Red background
4. **Summary and Next Steps** (1:08–1:30) — Purple background

### Required Deliverables (in `/home/ga/Videos/accessible_output/`):
1. **Closed captions**: `lecture_captions.srt` — Standard SRT format, 16+ entries
2. **Hardsubbed video**: `lecture_hardsubbed.mp4` — Captions burned into frames, no subtitle stream, 1920x1080
3. **Low-bandwidth version**: `lecture_lowband.mp4` — 480p resolution, reduced file size
4. **Section thumbnails**: `section_1.png` through `section_4.png` — One per section, >10KB
5. **Manifest**: `manifest.json` — Lists all deliverables with properties

## Expected Results
- Valid SRT file with 16+ properly timed entries
- Hardsubbed video with no separate subtitle stream
- 480p low-bandwidth video smaller than original
- 4 section thumbnail images
- Complete JSON manifest

## Verification Criteria (Pass Threshold: 55%)
- SRT captions: exists, valid format, 16+ entries, contains lecture content (5 pts)
- Hardsubbed video: exists, no sub stream, correct duration, resolution (6 pts)
- Low-bandwidth: exists, ≤480p, smaller file size (5 pts)
- Thumbnails: 4 images, >10KB each (6 pts)
- Manifest: valid JSON, lists categories, includes file sizes (4 pts)
- Total: 26 points

## Occupation Context
**Instructional Designer (SOC 25-9031)** — Higher Education industry
