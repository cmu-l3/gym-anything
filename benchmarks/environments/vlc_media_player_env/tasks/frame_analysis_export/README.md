# Frame Analysis Export Task

**Difficulty**: 🟡 Medium  
**Skills**: Frame-by-frame navigation, snapshot capture, precise video control  
**Duration**: 180 seconds  
**Steps**: ~50

## Objective

Navigate to a specific moment in a video using frame-by-frame controls to locate a brief visual event (red flash lasting 3 frames) and capture that exact frame as a snapshot.

## Task Description

The agent must:
1. Open a test video containing a red flash at timestamp ~1:15
2. Navigate to approximately 1:15 using timeline seek
3. Use frame-by-frame navigation (keyboard 'e') to find the exact frame with the red flash
4. Capture a snapshot of that frame
5. Save snapshot as `/home/ga/Pictures/analysis_frame.png`

## Scenario

A sports blogger is analyzing a controversial play from a game recording. The key moment happens in a 2-second window at 1:15, and they need to capture the exact frame where contact occurred. This simulates real-world workflows for sports analysis, film studies, research documentation, or content creation where frame precision matters.

## Expected Results

- Snapshot file created at `/home/ga/Pictures/analysis_frame.png`
- Image dimensions match video (1280x720)
- Captured frame shows the red flash indicator (center region has >15% red pixels)
- File size indicates proper quality (>50KB)

## Verification Criteria

1. ✅ **Snapshot Exists**: File found at specified location
2. ✅ **Image Quality**: Reasonable file size and correct resolution
3. ✅ **Correct Frame**: Red flash visible in center region

**Pass Threshold**: 70%

## Skills Tested

- Timeline navigation and seeking
- Frame-by-frame control usage
- Visual event identification
- Snapshot feature operation
- Precise timing and control

## Controls

- **Timeline Seek**: Click on progress bar or use `Ctrl+T` for jump-to-time dialog
- **Frame-by-Frame**: Press `e` to advance one frame forward
- **Snapshot**: Press `Shift+S` or Video → Take Snapshot
- **Advanced Controls**: View → Advanced Controls (shows frame-by-frame button)
- **Pause/Play**: `Space` key

## Notes

- The red flash appears for exactly 3 frames (~100ms at 30fps)
- Timeline seeking gets you close, but frame-by-frame is required for precision
- VLC's default snapshot naming is `vlcsnap-*.png`, may need to rename to match expected output
- Enable Advanced Controls for visual frame-by-frame button if needed