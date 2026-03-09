# Compare Restoration Quality Task

**Difficulty**: 🟡 Medium  
**Skills**: Multi-window management, synchronized playback, snapshot comparison  
**Duration**: 90 seconds  
**Steps**: ~40

## Objective

Set up synchronized comparison of two video files (original vs restored) to evaluate restoration quality at specific timestamps.

## Task Description

The agent must:
1. Two video files are provided: `original_scan.mp4` (unprocessed) and `restored_version.mp4` (professionally restored)
2. Open both videos in VLC for side-by-side comparison
3. Navigate to timestamp 00:15 (15 seconds) in both videos
4. Take snapshots from both videos at this timestamp
5. Name snapshots distinctively (include "original" and "restored" in filenames)

## Real-World Context

Maria runs a historical society and needs to compare restoration quality from two different services before committing to processing 40 hours of archival footage. She needs to examine specific frames side-by-side to evaluate detail preservation, especially in text and faces.

## Expected Results

- Two snapshots captured at approximately 00:15 timestamp
- Snapshots have distinctive names containing "original" and "restored"
- Both snapshots are valid images (>20 KB each)
- Evidence of synchronized comparison workflow

## Verification Criteria

1. ✅ **Original Snapshot Exists**: Snapshot with "original" in filename found
2. ✅ **Restored Snapshot Exists**: Snapshot with "restored" in filename found
3. ✅ **Snapshots Valid**: Both images have reasonable quality (>20 KB)
4. ✅ **Temporal Proximity**: Snapshots captured within 60 seconds of each other (same session)
5. ✅ **Multiple VLC Instances**: Evidence of multi-window workflow

**Pass Threshold**: 70%

## Skills Tested

- Multi-window/instance VLC management
- Synchronized playback coordination
- Timestamp navigation precision
- Snapshot capture and file naming
- Practical comparison workflow design

## Controls

- **Launch Multiple VLC**: Multiple instances can be opened separately
- **Snapshot**: `Shift+S` - Take snapshot
- **Seek**: `Shift+Right/Left` - Jump by 5 seconds
- **Pause**: `Space` - Pause/play toggle
- **File Rename**: Use file manager or command line to rename snapshots

## Notes

This task tests the ability to set up a practical comparison workflow. The agent may need to:
- Open two VLC windows simultaneously
- Manually synchronize playback positions
- Take snapshots from each window
- Rename files to distinguish between sources

The exact method for achieving synchronized comparison is flexible - creativity is encouraged!