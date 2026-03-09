# VLC Video Segment Extraction Task (`extract_video_segment@1`)

**Difficulty**: 🟡 Medium  
**Skills**: Video recording, precise timing, navigation  
**Duration**: 90 seconds  
**Steps**: ~35

## Objective

Extract a specific 30-second segment from a longer video file using VLC's built-in recording feature. This simulates a real-world scenario where an HR manager needs to isolate a specific incident from lengthy security footage.

## Task Description

The agent must:
1. VLC launches with a 10-minute security footage video
2. Navigate to timestamp 02:15 (2 minutes 15 seconds)
3. Start recording using the Record button
4. Let video play until 02:45 (30 seconds of footage)
5. Stop recording
6. Recorded segment is saved automatically

## Expected Results

- Recorded video file created in `/home/ga/Videos/`
- Filename pattern: `vlc-record-*.mp4` (or .avi, .mkv)
- Duration: approximately 30 seconds (27-33 seconds acceptable)
- File size: 3-15 MB (reasonable for 30-second segment)

## Verification Criteria

1. ✅ **Output File Exists**: Recording found with VLC naming pattern
2. ✅ **Created During Task**: File timestamp within task execution window
3. ✅ **File Size Appropriate**: 500KB < size < 50MB
4. ✅ **Duration Correct**: Video duration 27-33 seconds (30±3s)
5. ✅ **Valid Video Format**: Readable video with proper codec

**Pass Threshold**: 75% (4/5 criteria)

## Skills Tested

- Video timeline navigation
- Precise timestamp seeking
- Recording controls (Advanced Controls)
- Timing coordination
- Understanding of VLC recording feature
- File output awareness

## Controls

- **View → Advanced Controls**: Show recording button (if not visible)
- **Record button** (red circle icon): Toggle recording on/off
- **Playback → Jump to Specific Time** (Ctrl+T): Navigate to timestamp
- **Timeline scrubbing**: Click on progress bar to seek
- **Keyboard seeking**: Shift+Right (5s forward), Shift+Left (5s backward)

## Real-World Context

An HR manager is reviewing 10-minute security camera footage from an office incident. They need to extract only the critical 30-second segment (02:15 to 02:45) showing the actual incident to share with legal counsel. The entire video cannot be shared due to privacy concerns (shows other employees). VLC is the only tool available on their corporate laptop.

## Notes

- Recording captures exactly what's playing during record mode
- Default save location: `/home/ga/Videos/`
- Recording format matches source video codec
- Small timing variations (±3 seconds) are acceptable for human operators