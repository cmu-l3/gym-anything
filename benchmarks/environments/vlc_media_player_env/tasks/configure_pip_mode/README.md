# Configure Picture-in-Picture Mode Task

**Difficulty**: 🟡 Medium  
**Skills**: Window management, always-on-top configuration, spatial reasoning  
**Duration**: 120 seconds  
**Steps**: ~40

## Objective

Configure VLC for multitasking workflows by enabling "always-on-top" mode, resizing the video window to a compact size, and positioning it in a screen corner. This represents a common productivity scenario where a user needs to monitor video content while working in other applications.

## Task Description

The agent must:
1. Launch VLC with a training webinar video
2. Enable "Always on Top" mode (Video → Always on Top)
3. Resize VLC window to compact size (≤500x300 pixels)
4. Position window in a screen corner (preferably top-right or bottom-right)
5. Ensure video continues playing
6. Verify configuration persists

## Expected Results

- VLC playing video in always-on-top mode
- Window size ≤ 500x300 pixels (compact, non-obstructive)
- Window positioned in corner region (X > 70% screen width OR Y < 30% OR Y > 70% screen height)
- Video actively playing (not paused)
- Other windows can be focused without hiding VLC
- VLC preferences saved with always-on-top enabled

## Verification Criteria

1. ✅ **Config Enabled**: `video-on-top=1` in VLC config
2. ✅ **Window Property**: X11 always-on-top property set (`_NET_WM_STATE_ABOVE`)
3. ✅ **Compact Size**: Window ≤ 500x300 pixels
4. ✅ **Corner Position**: Window in screen corner region
5. ✅ **Playing & Visible**: Video playing and remains visible when other windows focused

**Pass Threshold**: 80% (4/5 criteria)

## Skills Tested

- VLC menu navigation (Video → Always on Top)
- Window management and resizing
- Spatial positioning and screen layout understanding
- Multi-application coordination
- Settings persistence
- X11 window property understanding

## Controls

- **Menu**: Video → Always on Top (or View → Always on top)
- **Window Resize**: Drag window edges or corners
- **Window Move**: Drag title bar to corner
- **Alternative**: Use keyboard shortcuts or preferences

## Real-World Context

This task simulates a remote worker monitoring a training webinar while simultaneously working on documents, emails, or spreadsheets. The video must remain visible above other windows without being obstructive.

## Notes

- Window size should be compact to minimize workspace obstruction
- Corner positioning prevents blocking central work area
- Always-on-top ensures video visibility during multitasking
- Configuration should persist across VLC sessions