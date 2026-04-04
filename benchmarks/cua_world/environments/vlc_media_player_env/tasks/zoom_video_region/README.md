# Zoom Video Region Task

**Difficulty**: 🟡 Medium  
**Skills**: Video effects, zoom/magnification, UI navigation  
**Duration**: 180 seconds  
**Steps**: ~40

## Objective

Configure VLC to zoom into video content by 200% (2x magnification) to make small text and UI elements readable in a tutorial video.

## Task Description

The agent must:
1. VLC launches with a high-resolution tutorial video containing small text
2. Navigate to video effects/adjustment settings
3. Enable interactive zoom functionality
4. Set zoom level to 200% (2x magnification)
5. Zoom settings persist in VLC configuration

## Expected Results

- Interactive zoom enabled in VLC config (`interactive-zoom=1`)
- Zoom level set to 2.0 or 200% (`zoom=2.0`)
- Video visibly magnified during playback
- Settings persisted to VLC configuration file

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Interactive Zoom Enabled**: `interactive-zoom=1` in config
3. ✅ **Zoom Level Correct**: Zoom value at 2.0 (±0.1 tolerance)

**Pass Threshold**: 70%

## Skills Tested

- Menu navigation (Tools → Effects and Filters)
- Video Effects panel interaction (Geometry tab)
- Understanding of video transformation effects
- Slider/parameter adjustment
- Settings persistence

## Controls

- **Menu**: Tools → Effects and Filters (Ctrl+E)
- **Tab**: Video Effects → Geometry
- **Checkbox**: Enable "Interactive Zoom"
- **Slider**: Adjust zoom factor to 2.0

## Notes

The zoom feature magnifies the center portion of the video. This is useful for:
- Reading small text in screen recordings
- Examining details in video content
- Accessibility purposes
- Focusing on specific regions of interest

VLC's zoom range typically goes from 0.25x to 4.0x, with 1.0 being normal size.