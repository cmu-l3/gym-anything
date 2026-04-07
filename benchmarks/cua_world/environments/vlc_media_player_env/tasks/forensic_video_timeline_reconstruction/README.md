# Forensic Video Timeline Reconstruction

## Difficulty
Very Hard

## Skills Tested
- Frame-by-frame video navigation
- Precise timestamp identification
- Screenshot/snapshot capture at specific timestamps
- Video segment extraction
- Forensic documentation and JSON report generation
- Critical analysis (rejecting inaccurate source data)

## Objective
Review dashcam footage, identify exact timestamps of 5 visual events, capture forensic snapshots, extract evidence clips, and produce a corrected timeline replacing the inaccurate initial incident log.

## Real-World Scenario
An insurance claims investigator reviewing dashcam footage of a reported multi-vehicle collision. The initial incident log from witness statements contains inaccurate timestamps. The investigator must watch the actual footage, identify when each event truly occurs, and produce forensic-quality evidence with corrected timestamps for the claims file.

## Task Description
- **Dashcam footage**: `/home/ga/Videos/dashcam_footage.mp4` (3 minutes, 1280x720)
- **Incident log**: `/home/ga/Documents/incident_log.txt` (contains 5 events with WRONG timestamps)

The video contains 5 distinct visual events marked by colored indicator bars and text overlays:
- Event A (red bar): "IMPACT"
- Event B (green bar): "SWERVE"
- Event C (blue bar): "DEBRIS"
- Event D (yellow bar): "STOP"
- Event E (white bar): "REVERSE"

**IMPORTANT**: The timestamps in the incident log are from witness statements and are **inaccurate**. The agent must identify the correct timestamps from the actual video.

### Required Deliverables:
1. Forensic snapshot of each event (saved as images)
2. Corrected timeline at `/home/ga/Documents/corrected_timeline.json`
3. 5-second evidence clips (centered on each event) at `/home/ga/Videos/evidence_clips/`

## Expected Results
- 5 forensic-quality snapshots
- JSON timeline with 5 events and corrected timestamps
- 5 video clips (~5 seconds each)

## Verification Criteria (Pass Threshold: 55%)
- Timeline: valid JSON, 5 events, each timestamp within ±2s of ground truth (8 pts)
- Wrong-target gate: using incident log timestamps → 0 credit for timestamps
- Snapshots: 5 valid images >10KB (7 pts)
- Evidence clips: 5 clips at ~5s duration (10 pts)
- Total: 25 points

## Occupation Context
**Claims Adjuster/Investigator (SOC 13-1031)** — Insurance industry
