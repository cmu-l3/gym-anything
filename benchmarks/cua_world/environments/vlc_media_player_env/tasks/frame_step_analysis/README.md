# Frame-by-Frame Tutorial Analysis Task

**Difficulty**: 🟡 Medium  
**Skills**: Frame stepping, visual analysis, precision navigation  
**Duration**: 120 seconds  
**Steps**: ~40

## Objective

Use VLC's frame-by-frame navigation to analyze a tutorial video and identify a specific visual marker that appears briefly, then capture a snapshot at that exact frame.

## Task Description

The agent must:
1. Open VLC with a tutorial video containing a red square marker at a specific frame
2. Navigate to the approximate region (5-10 seconds)
3. Pause the video
4. Use frame-by-frame stepping (press 'e' key) to find the exact frame
5. Identify the frame where the red square marker appears centered
6. Capture a snapshot at that precise frame using Shift+S

## Expected Results

- Snapshot file created in `/home/ga/Pictures/vlc/`
- Snapshot contains the red square marker (100x100px) centered in frame
- Marker is clearly visible and properly positioned

## Verification Criteria

1. ✅ **Snapshot Exists**: Snapshot file found and valid
2. ✅ **Red Marker Detected**: Computer vision confirms red square present
3. ✅ **Proper Centering**: Marker located in center region (±20%)
4. ✅ **Complete Marker**: Full square visible, not cut off or partial
5. ✅ **Quality Maintained**: File has good size and resolution

**Pass Threshold**: 75%

## Skills Tested

- Frame-by-frame navigation (keyboard hotkey: 'e')
- Visual pattern recognition
- Precise timing and patience
- Snapshot capture integration
- Multi-modal control (seek bar + keyboard)

## Real-World Use Case

This simulates a common scenario where users need to examine tutorial videos in detail:
- Following cooking demonstrations with fast knife techniques
- Analyzing sports form or technique frame-by-frame
- Understanding complex visual instructions in how-to videos
- Capturing exact moments for reference materials

## Controls

- **Space**: Pause/Play
- **e**: Advance one frame forward (while paused)
- **Shift+e**: Go one frame backward (while paused)
- **Shift+S**: Take snapshot
- **Left/Right Arrow**: Seek ±3 seconds
- **Shift+Left/Right**: Seek ±10 seconds