# Enable HDR Tone Mapping Task

**Difficulty**: 🟡 Medium  
**Skills**: Advanced preferences navigation, video filter configuration, color space understanding  
**Duration**: 90 seconds  
**Steps**: ~35

## Objective

Enable VLC's HDR-to-SDR tone mapping feature to properly display HDR (High Dynamic Range) videos on standard SDR (Standard Dynamic Range) displays.

## Task Description

The agent must:
1. Open VLC with an HDR test video that looks washed out
2. Navigate to advanced video filter preferences
3. Enable the tone mapping filter
4. Configure tone mapping method for HDR10-to-SDR conversion
5. Settings persist in VLC configuration

## Real-World Context

Modern smartphones and cameras record videos in HDR10 by default, but most laptop/desktop monitors only support SDR. Without tone mapping, HDR videos display with incorrect colors, washed-out appearance, and poor contrast. VLC's tone mapping filter converts HDR color space to SDR for proper viewing.

## Expected Results

- Tone mapping filter enabled in VLC preferences
- Tone mapping method configured (e.g., Hable, Reinhard, Mobius)
- Settings saved to VLC config file (`~/.config/vlc/vlcrc`)
- HDR video displays with proper colors and contrast

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Tone Mapping Filter**: Tone mapping or adjust filter enabled in video-filter
3. ✅ **Settings Valid**: Tone mapping configuration is valid and persistent

**Pass Threshold**: 70%

## Skills Tested

- Advanced preferences navigation (switching from Simple to All)
- Video filter menu exploration
- Understanding of HDR/SDR color spaces
- Settings persistence verification
- Problem-solving (finding non-obvious settings)

## Controls

- **Menu**: Tools → Preferences → Show settings: All
- **Navigation**: Video → Filters → Tone mapping
- **Checkbox**: Enable "Tone mapping" filter
- **Dropdown**: Select tone mapping method

## Navigation Path

1. Tools → Preferences (Ctrl+P)
2. Click "All" radio button (bottom-left) to show advanced settings
3. Navigate to: Video → Filters
4. Find and enable "Tone mapping" or "Image adjust" filter
5. Configure tone mapping parameters if available
6. Click Save

## Notes

- VLC 3.0+ required for tone mapping support
- The HDR test video is encoded with BT.2020 color space and PQ transfer function
- Tone mapping is computationally expensive but necessary for correct HDR display on SDR screens
- Common tone mapping operators: Hable (Uncharted), Reinhard, Mobius, Clip