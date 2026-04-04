# Deinterlace VHS Footage Task

**Difficulty**: 🟡 Medium  
**Skills**: Video quality restoration, deinterlacing filters, settings configuration  
**Duration**: 60 seconds  
**Steps**: ~30

## Objective

Configure VLC Media Player to apply deinterlacing to a digitized VHS video that exhibits interlacing artifacts (horizontal comb lines during motion).

## Task Description

The agent must:
1. VLC launches with an interlaced video file showing comb artifacts
2. Navigate to VLC's deinterlacing settings
3. Enable deinterlacing filter
4. Select an appropriate deinterlacing mode
5. Ensure settings persist in VLC configuration

## Expected Results

- Deinterlacing enabled in VLC configuration
- Deinterlace mode set to a valid algorithm (e.g., linear, yadif, bob)
- Video playback shows smooth motion without interlacing artifacts
- Settings persist after closing VLC

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Deinterlacing Enabled**: Deinterlace setting found in config
3. ✅ **Valid Mode**: Deinterlace mode is set to a valid algorithm

**Pass Threshold**: 70%

## Skills Tested

- Video filter menu navigation
- Understanding of interlacing/deinterlacing concepts
- Settings persistence understanding
- VLC preferences interface

## Controls

- **Menu**: Tools → Preferences → Video
- **Advanced**: Show settings: All → Video → Filters → Deinterlace
- **Keyboard**: `D` to cycle through deinterlace modes (in some VLC versions)

## Background Context

VHS tapes used interlaced video (alternating odd/even scan lines), which causes visible "comb" artifacts on modern progressive-scan displays. Deinterlacing converts interlaced video to progressive format for smooth playback.

## Notes

Valid deinterlace modes include: blend, bob, discard, linear, mean, phosphor, x, yadif, yadif2x, ivtc. Any of these modes is acceptable for task completion.