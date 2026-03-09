# Verify Display Calibration Task

**Difficulty**: 🟡 Medium  
**Skills**: Display configuration, video filter management, settings reset  
**Duration**: 90-120 seconds  
**Steps**: ~35

## Objective

Configure VLC Media Player to display a color calibration test pattern with zero color manipulation, ensuring all video filters, adjustments, and color transformations are disabled for accurate display calibration.

## Task Description

The agent must:
1. VLC launches with a color calibration test video loaded but filters/adjustments are active
2. Navigate to Effects and Filters menu (Tools → Effects and Filters)
3. Disable all active video filters
4. Reset all video adjustments to neutral values (brightness, contrast, gamma, saturation)
5. Disable hardware color correction if enabled
6. Play the test pattern video to completion

## Expected Results

- All video filters disabled in VLC configuration
- Video adjustments at neutral values (1.0 for brightness, contrast, gamma, saturation)
- Hardware color adjustments disabled
- Test pattern video played to completion
- Configuration persisted in VLC preferences

## Verification Criteria

1. ✅ **No Video Filters**: All video filters disabled
2. ✅ **Neutral Adjustments**: Brightness, contrast, gamma, saturation at default (~1.0)
3. ✅ **Hardware Filters Disabled**: No GPU-based color correction active
4. ✅ **Video Played**: Test pattern video was played to completion
5. ✅ **Config Persisted**: Settings saved to VLC configuration file

**Pass Threshold**: 70% (5/7 criteria points)

## Skills Tested

- Effects and filters menu navigation
- Understanding of video adjustment parameters
- Configuration management across multiple dialogs
- Understanding of "neutral" vs "modified" states
- Settings persistence verification

## Controls

- **Menu**: Tools → Effects and Filters (Ctrl+E)
- **Video Effects Tab**: Disable filters and reset adjustments
- **Keyboard**: Space to play/pause

## Real-World Context

Graphic designers, photographers, and video editors need to verify their monitors display accurate colors. This requires viewing professional test patterns (SMPTE color bars, grayscale ramps) without any color manipulation from the media player. Any filters or adjustments would invalidate the calibration test.

## Notes

The test pattern is a 60-second SMPTE color bars video with grayscale ramps. VLC starts with some filters and adjustments intentionally enabled to simulate previous use.