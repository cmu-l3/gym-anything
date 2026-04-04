# Add Timecode Overlay Task

**Difficulty**: 🟡 Medium  
**Skills**: Video effects, overlay configuration, professional workflow  
**Duration**: 90 seconds  
**Steps**: ~35

## Objective

Configure VLC to display a visible timecode overlay on video playback. This enables frame-accurate collaboration and review workflows common in film/video production, education, and legal contexts.

## Task Description

The agent must:
1. VLC launches with a test video
2. Navigate to Effects and Filters (Tools → Effects and Filters)
3. Enable timecode overlay in Video Effects → Overlay tab
4. Configure timecode to be visible during playback
5. Optionally capture a screenshot to verify visibility

## Expected Results

- Timecode overlay enabled in VLC configuration
- Timecode visible during video playback (HH:MM:SS format)
- Configuration persists in vlcrc file
- Optional: Screenshot showing timecode overlay

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Timecode Enabled**: Time overlay filter is enabled in config
3. ✅ **Verification Evidence**: Screenshot or output confirms visibility

**Pass Threshold**: 70%

## Skills Tested

- Effects and Filters menu navigation
- Video overlay configuration
- Understanding of professional video workflows
- Settings persistence verification
- Optional: Screenshot capture for verification

## Controls

- **Menu**: Tools → Effects and Filters (Ctrl+E)
- **Tab**: Video Effects → Overlay
- **Checkbox**: Enable "Time" overlay
- **Optional**: Shift+S to capture screenshot for verification

## Real-World Context

Film students, video editors, and reviewers use timecode overlays to reference specific frames during collaborative critique sessions (e.g., "At 00:02:15, the transition feels abrupt"). This is essential for frame-accurate feedback and professional video production workflows.

## Notes

VLC's time overlay displays the current playback time as HH:MM:SS format. The overlay position and format can be configured. For verification, we check the vlcrc configuration file for the time-overlay setting.