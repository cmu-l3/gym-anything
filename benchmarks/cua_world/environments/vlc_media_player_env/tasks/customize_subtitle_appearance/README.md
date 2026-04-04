# Customize Subtitle Appearance Task

**Difficulty**: 🟡 Medium  
**Skills**: Subtitle customization, preferences configuration, accessibility  
**Duration**: 90 seconds  
**Steps**: ~35

## Objective

Configure VLC's subtitle appearance settings to improve readability by adding contrast and increasing font size for large-screen viewing.

## Task Description

The agent must:
1. Open VLC's advanced preferences
2. Navigate to subtitle/text renderer settings
3. Increase subtitle font size for large screen viewing
4. Add a semi-transparent dark background for contrast
5. Save settings to persist changes

## Scenario

You are preparing a video with subtitles for a community screening. When testing, you notice the default white subtitle text is invisible during bright scenes (outdoor daylight, snow). You need to configure VLC to make subtitles readable against ANY background.

## Expected Results

- Subtitle font size increased to ≥30 pixels (default ~20)
- Semi-transparent dark background enabled (opacity ≥128/255)
- Background color is dark (for contrast with white text)
- Settings persist in VLC configuration

## Verification Criteria

1. ✅ **Font Size Increased**: Font size ≥30 pixels
2. ✅ **Background Enabled**: Background opacity ≥128/255
3. ✅ **Dark Background**: Background color is dark (<50 RGB brightness)

**Pass Threshold**: 70%

## Skills Tested

- Advanced preferences navigation
- Understanding of text rendering options
- Accessibility awareness
- Configuration persistence
- Problem-solving (finding buried settings)

## Controls

- **Menu**: Tools → Preferences → Show All Settings (bottom left)
- **Navigate**: Video → Subtitles/OSD → Text renderer
- **Settings**: 
  - Font size
  - Background opacity
  - Background color
- **Save**: Click "Save" button to persist changes

## Files Available

- Test video: `/home/ga/Videos/test_movie.mp4` (varying brightness)
- Subtitles: `/home/ga/Videos/test_movie.srt`

## Notes

VLC's subtitle appearance settings are in advanced preferences, not the simple preferences. You must click "Show All Settings" at the bottom left of the Preferences window to access them.