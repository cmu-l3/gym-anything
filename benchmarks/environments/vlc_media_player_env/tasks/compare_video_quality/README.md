# Compare Video Quality Task

**Difficulty**: 🟡 Medium  
**Skills**: Multiple instance management, window positioning, synchronization  
**Duration**: 3-4 minutes  
**Steps**: ~50

## Objective

Open two video files simultaneously in separate VLC instances, synchronize them to the same timestamp (2:30), and capture screenshots for side-by-side quality comparison.

## Real-World Scenario

You downloaded a classic film from two sources. One is labeled "HD Remaster - 4.2GB" and the other is "Original Upload - 1.8GB". Both claim to be 1080p, but you suspect one is actually an upscaled SD source. You need to visually compare them at the same scene to determine which version has better actual quality before deleting one.

## Task Description

The agent must:
1. Launch two separate VLC instances
2. Load `version_a.mp4` in first instance
3. Load `version_b.mp4` in second instance
4. Seek both videos to exactly 2:30 (150 seconds)
5. Position windows side-by-side for comparison
6. Capture screenshots of both at the same timestamp
7. Save screenshots as `version_a_frame.png` and `version_b_frame.png`

## Expected Results

- Two VLC windows running simultaneously
- Both videos paused at 2:30
- Screenshots saved to `/home/ga/Pictures/comparison/`
- Both screenshots are valid images (>50KB each)

## Verification Criteria

1. ✅ **Both Screenshots Exist**: Both PNG files found
2. ✅ **Screenshot Quality**: Both images have reasonable size (>50KB)
3. ✅ **Valid Images**: Both are valid image files with proper dimensions
4. ✅ **Captured Together**: Screenshots taken within reasonable time window

**Pass Threshold**: 75%

## Skills Tested

- Multiple VLC instance management
- Window positioning and arrangement
- Synchronized seeking across instances
- Screenshot capture coordination
- Understanding of comparison workflows

## Controls

- **Launch separate instances**: `vlc --no-one-instance file.mp4`
- **Seek to time**: `Ctrl+T` → Enter timestamp
- **Take snapshot**: `Shift+S`
- **Position windows**: `wmctrl` or manual dragging

## Notes

This task requires managing two VLC instances simultaneously, which tests the agent's ability to coordinate actions across multiple application windows - a common real-world workflow for comparison tasks.