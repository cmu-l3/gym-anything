# Fix TV Overscan Task

**Difficulty**: 🟡 Medium  
**Skills**: Video filter configuration, display settings, advanced preferences  
**Duration**: 180 seconds  
**Steps**: ~40

## Objective

Configure VLC to add black padding/margins around video playback to compensate for TV overscan, ensuring the entire video frame (including edges with subtitles) is visible on an overscanned display.

## Task Description

The agent must:
1. VLC launches with a test video containing edge markers
2. Navigate to VLC's video effects/filters preferences
3. Enable canvas or padding filter to add margins around video
4. Configure padding to add ~5-10% margins on all sides
5. Settings persist in VLC configuration

## Expected Results

- Canvas/padding video filter enabled in VLC config
- Padding parameters configured appropriately
- Settings saved to VLC preferences (vlcrc)
- Edge content would be visible within padded area

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Filter Enabled**: Canvas/padding filter is enabled
3. ✅ **Padding Configured**: Padding parameters are set

**Pass Threshold**: 70%

## Skills Tested

- Advanced preferences navigation
- Video filter understanding
- Configuration persistence
- Display compatibility problem-solving

## Context

Overscan is a legacy TV feature that zooms the image by 5-10%, cutting off edges. This is common on older TVs and projectors. When you can't access the TV's settings (no remote, public display), VLC-side padding is the solution.

## Controls

- **Tools → Effects and Filters** (Ctrl+E) → Video Effects → Geometry
- **Tools → Preferences** (Ctrl+P) → Show All Settings → Video → Filters
- Look for "Canvas", "Transform", or "Padding" options