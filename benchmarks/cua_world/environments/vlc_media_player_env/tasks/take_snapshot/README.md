# Take Snapshot Task

**Difficulty**: 🟡 Medium  
**Skills**: Snapshot feature, timing  
**Duration**: 60 seconds  
**Steps**: ~25

## Objective

Capture a snapshot at a specific timestamp in a video using VLC's snapshot feature.

## Task Description

The agent must:
1. VLC launches with video
2. Seek to a specific timestamp (e.g., 5 seconds)
3. Capture a snapshot using Shift+S or Video menu

## Expected Results

- Snapshot file created in `/home/ga/Pictures/vlc/`
- Snapshot has reasonable quality (>50 KB)
- Snapshot captured at target timestamp

## Verification Criteria

1. ✅ **Snapshot Captured**: Snapshot file exists
2. ✅ **Snapshot Quality**: Image has reasonable size/quality
3. ✅ **Task Completed**: Completion marker present

**Pass Threshold**: 65%

## Skills Tested

- Snapshot hotkey usage (Shift+S)
- Video menu navigation
- Timestamp seeking
- File output verification

## Controls

- **Keyboard**: `Shift+S` - Take snapshot
- **Menu**: Video → Take Snapshot
