# Scan Security Footage Task

**Difficulty**: 🟡 Medium  
**Skills**: Long video navigation, playback speed control, snapshot capture, timestamp precision  
**Duration**: 90-120 seconds  
**Steps**: ~40

## Objective

Review security camera footage to locate and document a suspicious incident. Navigate efficiently through a long video using fast playback, identify the incident, and capture snapshot evidence.

## Task Description

You are a small business owner reviewing overnight security footage. An employee reported suspicious activity around 3:00 AM (approximately 5 hours into the 8-hour recording). You need to:

1. Navigate to approximately 5 hours into the video (~3:00 AM timestamp)
2. Use fast playback (3-5x speed) to scan efficiently
3. Identify when the incident occurs (person appears and interacts with objects)
4. Return to normal playback when incident is found
5. Capture 2-3 snapshots during the incident for documentation

## Expected Results

- Video position reached ~5:15:00 (5 hours, 15 minutes)
- Playback speed increased for scanning
- At least 2 snapshots captured during incident window (5:15:00 - 5:17:00)
- Snapshots saved to `/home/ga/Pictures/security_evidence/`

## Verification Criteria

1. ✅ **Snapshot Count**: At least 2 snapshots captured
2. ✅ **Snapshot Quality**: Valid image files (>50 KB, reasonable resolution)
3. ✅ **Timestamp Accuracy**: Snapshots captured during incident window
4. ✅ **Temporal Separation**: Snapshots from different moments (≥3s apart)

**Pass Threshold**: 70%

## Skills Tested

- Efficient navigation in long videos
- Playback speed manipulation
- Visual pattern recognition (identifying activity)
- Snapshot capture timing
- Evidence documentation workflow

## Controls

- **Seek**: Click timeline, Media → Go to Time, Ctrl+T
- **Speed up**: Playback → Speed → Faster, or `]` key
- **Speed down**: Playback → Speed → Slower, or `[` key
- **Normal speed**: Playback → Speed → Normal, or `=` key
- **Snapshot**: Video → Take Snapshot, or `Shift+S`

## Notes

The security video simulates 8-hour overnight footage with timestamp overlay. Most of the video is static (empty parking lot), but a clear incident occurs at 5:15:30 (5 hours, 15 minutes, 30 seconds into the recording). The incident lasts approximately 45 seconds.