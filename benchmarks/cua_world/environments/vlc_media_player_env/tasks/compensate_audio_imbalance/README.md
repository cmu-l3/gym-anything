# Compensate Audio Imbalance Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio accessibility, balance adjustment, settings persistence  
**Duration**: 60 seconds  
**Steps**: ~25

## Objective

Configure VLC's audio balance to compensate for hardware imbalance (defective left earbud) by shifting the stereo balance to the left.

## Task Description

The agent must:
1. VLC launches with an audio file
2. Access audio balance controls
3. Adjust balance to shift audio toward left channel (compensate for weak left earbud)
4. Balance should be set between 60-80% toward left (-0.3 to -0.8 in VLC scale)
5. Test the setting by playing audio
6. Ensure setting persists in configuration

## Expected Results

- Audio balance set to value between -0.3 and -0.8 (shifted left)
- Balance value persisted in VLC config file
- Not too extreme (< -0.85) to avoid overcompensation
- Not too subtle (> -0.25) to actually help

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Balance Set**: Audio balance setting is present and in correct range
3. ✅ **Balance Appropriate**: Balance is negative and within target range

**Pass Threshold**: 70%

## Skills Tested

- Audio effects/settings navigation
- Balance slider adjustment or keyboard shortcuts
- Understanding of stereo audio concepts
- Settings persistence verification
- Accessibility feature usage

## Controls

- **Menu**: Audio → Audio Device / Audio Effects
- **Keyboard**: 
  - `Shift+Left`: Shift balance left
  - `Shift+Right`: Shift balance right
- **Effects Dialog**: Tools → Effects and Filters → Audio Effects → Spatializer

## Real-World Context

This task addresses a common accessibility and hardware issue where:
- Earbuds/headphones have one channel quieter than the other
- Users have asymmetric hearing loss
- Audio hardware has manufacturing defects
- Software compensation can provide a practical workaround

## Notes

Audio balance in VLC:
- Range: -1.0 (full left) to +1.0 (full right)
- Default: 0.0 (centered)
- Stored in vlcrc as: `audio-balance=-0.500000`