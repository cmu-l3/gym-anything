# Normalize Audio Dynamics Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio effects navigation, accessibility awareness, dynamic range compression  
**Duration**: 90-120 seconds  
**Steps**: ~40

## Objective

Enable VLC's audio dynamic range compressor to make a video with inconsistent audio levels (quiet dialogue, loud sound effects) more comfortable to watch. This addresses a real accessibility need for elderly users and those with hearing challenges.

## Task Description

**User Context**: Margaret, a 72-year-old grandmother, has a video where the dialogue is barely audible but the background sounds are painfully loud. She needs to "even out" the audio levels without constantly adjusting the volume.

The agent must:
1. VLC launches with a video that has exaggerated dynamic range
2. Navigate to VLC's audio effects settings
3. Enable the dynamic range compressor
4. Configure compression parameters (or use defaults)
5. Play video briefly to ensure settings take effect
6. Settings persist in VLC configuration

## Expected Results

- Audio compressor filter enabled in VLC config
- Compressor parameters configured (not default/disabled)
- Video played with compression active
- Settings persist after closing VLC

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Compressor Enabled**: "compressor" found in audio-filter chain
3. ✅ **Parameters Set**: Compressor parameters configured

**Pass Threshold**: 70%

## Skills Tested

- Audio effects menu navigation
- Understanding of dynamic range compression
- Settings persistence verification
- Accessibility feature usage

## Controls

- **Menu**: Tools → Effects and Filters (Ctrl+E) → Audio Effects → Compressor
- **Enable**: Check "Enable" checkbox in Compressor tab
- **Parameters**: Adjust threshold, ratio, attack, release (defaults usually work)
- **Test**: Play video to hear the effect

## Real-World Impact

This task addresses a genuine accessibility problem:
- Helps elderly users and people with hearing loss
- Useful for night-time viewing (avoiding loud sounds)
- Improves dialogue intelligibility in poorly mixed content
- Common issue with home videos, lectures, and older media

## Notes

- VLC's compressor settings are in Tools → Effects and Filters → Audio Effects → Compressor
- The compressor "evens out" audio by reducing the volume of loud parts and increasing quiet parts
- Default parameters usually work well; aggressive settings can sound unnatural
- The effect is applied in real-time during playback