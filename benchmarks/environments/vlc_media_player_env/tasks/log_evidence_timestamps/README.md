# Log Evidence Timestamps Task

**Difficulty**: 🟡 Medium  
**Skills**: Documentation, precision observation, timestamp tracking  
**Duration**: 180 seconds  
**Steps**: ~50

## Objective

Review evidence footage and create a precise timestamp log documenting when specific events occur in the video.

## Task Description

The agent must:
1. VLC launches with evidence footage video
2. Watch the video and identify 5 distinct events
3. Record exact timestamps for each event
4. Create a structured log file with timestamps and descriptions
5. Optionally capture snapshots at event times

## Expected Results

- Log file created at `/home/ga/Documents/evidence_log.txt`
- Contains timestamps for at least 4 of 5 events
- Timestamps accurate within ±2 seconds of actual event times
- Events listed in chronological order
- Bonus: Snapshots captured for 3+ events

## Verification Criteria

1. ✅ **Log File Exists**: Timestamp log file found and readable
2. ✅ **Timestamp Count**: Log contains 4+ valid timestamps
3. ✅ **Timestamp Accuracy**: Timestamps match events within ±2s tolerance
4. ✅ **Chronological Order**: Events listed sequentially
5. 🌟 **Bonus**: 3+ snapshots captured

**Pass Threshold**: 80% (4/5 events matched)

## Skills Tested

- Video playback control (play, pause, seek)
- Precision observation and timing
- Timestamp tracking from VLC display
- Structured documentation
- Optional: Snapshot capture (Shift+S)
- File creation and organization

## Real-World Context

Legal professionals, investigators, and journalists regularly need to document precise timestamps of events in video evidence. This workflow is critical for court proceedings, insurance claims, and investigative reporting where timing and sequence of events matter.

## Controls

- **Space**: Play/Pause
- **Shift+Right/Left**: Seek forward/backward
- **Shift+S**: Take snapshot
- **Timeline**: Click to jump to position

## Notes

The evidence footage contains visual markers at specific times. Timestamps can be noted in various formats (HH:MM:SS, MM:SS, or MM:SS.mmm). Focus on accuracy and chronological ordering.