# Apply Effects Task

**Difficulty**: 🟡 Medium  
**Skills**: Video effects, adjustments menu  
**Duration**: 60 seconds  
**Steps**: ~30

## Objective

Apply video effects (brightness and/or contrast adjustments) to a playing video using VLC's effects and filters menu.

## Task Description

The agent must:
1. Open VLC with a video playing
2. Navigate to the effects menu (Tools → Effects and Filters)
3. Enable video effects (adjust filter)
4. Modify brightness and/or contrast settings
5. Effects settings persist in VLC configuration

## Expected Results

- Video filter enabled in VLC config
- Brightness and/or contrast values modified from default (1.0)
- Effects visible in video playback

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Filter Enabled**: Video effects filter is enabled
3. ✅ **Effects Applied**: Brightness or contrast values modified

**Pass Threshold**: 70%

## Skills Tested

- Menu navigation (Tools → Effects and Filters)
- Effects panel interaction
- Slider adjustment
- Understanding of video effects
- Settings persistence

## Controls

- **Menu**: Tools → Effects and Filters (or Ctrl+E)
- **Video Effects tab**: Enable "Image adjust" filter
- **Sliders**: Adjust brightness, contrast, saturation, etc.

## Notes

Brightness and contrast values in VLC config are stored as floating point numbers where 1.0 is the default (no change). Values can range from 0.0 to 2.0 or higher.
