# Slow Audio Preserve Pitch Task

**Difficulty**: 🟡 Medium  
**Skills**: Playback speed control, audio effects understanding  
**Duration**: 90-120 seconds  
**Steps**: ~35

## Objective

Configure VLC to play a music tutorial video at 65% speed (0.65x) while preserving the original audio pitch, allowing musicians to learn complex passages without distortion.

## Task Description

The agent must:
1. VLC launches with a guitar tutorial video
2. Configure playback speed to exactly 0.65x (65% of normal speed)
3. Ensure audio pitch preservation (time-stretching) is enabled
4. Settings persist in VLC configuration

## Expected Results

- Playback speed set to 0.65x (±0.02 tolerance)
- Audio time-stretching enabled (no "chipmunk effect")
- Settings saved in VLC config file
- Video plays smoothly at reduced speed with true-to-tone audio

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Speed Correct**: Playback rate = 0.65x (±0.02 tolerance)
3. ✅ **Pitch Preserved**: Audio time-stretch enabled

**Pass Threshold**: 80%

## Skills Tested

- Playback speed menu navigation
- Understanding of speed vs. pitch concepts
- Audio effects configuration
- Precision numeric input
- Settings persistence verification

## Controls

- **Menu**: Playback → Speed → Custom (enter 0.65)
- **Menu**: Tools → Preferences → Audio → Enable time-stretching
- **Keyboard**: `[` to slow down, `]` to speed up (incremental)

## Notes

Musicians and transcribers use this feature extensively. VLC's time-stretching preserves pitch so the audio remains at the correct musical notes even when slowed down, unlike simple resampling which would lower the pitch (chipmunk effect).