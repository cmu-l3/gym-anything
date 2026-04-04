# Configure Night Viewing Mode Task

**Difficulty**: 🟡 Medium  
**Skills**: Video adjustment, preferences management, color filtering  
**Duration**: 180 seconds  
**Steps**: ~25

## Objective

Configure VLC to apply a persistent "night viewing mode" that reduces overall brightness and adds a warm color filter (reduces blue light) for comfortable late-night viewing in dark rooms.

## Task Description

The agent must:
1. Open VLC's video effects menu
2. Enable the "Image adjust" filter
3. Reduce brightness or gamma to 60-75% of default
4. Optionally apply warm color adjustments (hue shift)
5. Ensure settings persist across VLC restarts

## Expected Results

- Image adjust filter enabled in VLC configuration
- Brightness or gamma reduced to comfortable levels (0.5-0.8)
- Settings persist in vlcrc file
- Video remains watchable (not too dark)

## Verification Criteria

1. ✅ **Filter Enabled**: Image adjust filter is active
2. ✅ **Brightness/Gamma Reduced**: Values in 0.5-0.8 range
3. ✅ **Settings Persist**: Configuration saved to vlcrc

**Bonus**: Warm color filter applied (hue adjustment)

**Pass Threshold**: 80%

## Skills Tested

- Video effects menu navigation (Tools → Effects and Filters)
- Understanding brightness vs. gamma adjustments
- Settings persistence configuration
- Color filter application
- Balancing adjustments for usability

## Controls

- **Menu**: Tools → Effects and Filters (Ctrl+E)
- **Video Effects Tab**: Essential → Image adjust
- **Sliders**: Brightness, Gamma, Hue, Contrast

## Real-World Context

This task simulates a common use case: watching movies in bed late at night. Bright whites and blue light from videos can cause eye strain and disrupt sleep. Users need VLC-specific adjustments that don't affect other applications or system-wide brightness.