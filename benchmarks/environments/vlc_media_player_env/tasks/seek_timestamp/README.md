# Seek Timestamp Task

**Difficulty**: 🟢 Easy  
**Skills**: Timeline navigation, timestamp precision  
**Duration**: 40 seconds  
**Steps**: ~20

## Objective

Navigate to a specific timestamp (15 seconds) in a video using VLC's seek controls.

## Task Description

The agent must:
1. VLC starts with video paused
2. Seek to the 15-second mark
3. Capture snapshot to verify position

## Expected Results

- Video seeked to approximately 15 seconds
- Snapshot captured at target position
- Seek operation completed successfully

## Verification Criteria

1. ✅ **Snapshot Captured**: Snapshot file exists
2. ✅ **Snapshot Quality**: Image has reasonable size/quality
3. ✅ **Task Completed**: Completion marker present

**Pass Threshold**: 65%

## Skills Tested

- Seek bar interaction (click and drag)
- Keyboard shortcuts for seeking
- Time display reading
- Snapshot feature usage

## Controls

- **GUI**: Click on progress bar
- **Keyboard**:
  - `Shift+Right`: Jump forward 5s
  - `Shift+Left`: Jump backward 5s
  - `Shift+S`: Take snapshot
