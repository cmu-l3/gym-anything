# Correct Color Space Task

**Difficulty**: 🟡 Medium  
**Skills**: Color correction, video effects, display calibration  
**Duration**: 90 seconds  
**Steps**: ~35

## Objective

Fix a video with incorrect color space display (washed out, greenish tint) by adjusting VLC's color correction settings.

## Task Description

The agent must:
1. Open a video with incorrect colors (washed out, greenish tint)
2. Navigate to VLC's video effects menu (Tools → Effects and Filters)
3. Apply color corrections:
   - Increase gamma to restore black levels
   - Adjust hue to remove greenish tint
   - Optionally adjust saturation
4. Save settings to persist corrections

## Expected Results

- Video colors corrected using VLC's adjust filter
- Gamma increased (1.2-1.8 range)
- Hue shifted negative (-50 to -5) to remove green tint
- Settings persisted in VLC configuration

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Adjust Filter Enabled**: Video adjust filter is active
3. ✅ **Gamma Corrected**: Gamma value increased appropriately
4. ✅ **Hue Corrected**: Hue shifted negative to remove green

**Pass Threshold**: 70%

## Skills Tested

- Video effects menu navigation
- Understanding of color correction (gamma, hue, saturation)
- Slider precision adjustment
- Visual assessment of color issues
- Settings persistence

## Controls

- **Menu**: Tools → Effects and Filters (or Ctrl+E)
- **Video Effects tab**: Enable "Image adjust" checkbox
- **Sliders**: 
  - Gamma: Adjust to ~1.3-1.5
  - Hue: Adjust to ~-20 to -30
  - Saturation: Optionally increase to ~1.1-1.2

## Real-World Context

This task simulates a common problem where video files exported with incorrect color space metadata appear washed out or tinted when played. Content creators often need to quickly adjust display settings to review footage properly before re-encoding.