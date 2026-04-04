# Adjust Audio Balance Task

**Difficulty**: 🟡 Easy-Medium  
**Skills**: Audio effects navigation, configuration persistence, slider manipulation  
**Duration**: 90 seconds  
**Steps**: ~35

## Objective

Adjust VLC's audio balance/stereo panning to strongly favor the left channel, simulating a scenario where the right earphone is broken or the user has hearing loss in the right ear.

## Task Description

The agent must:
1. VLC launches with an audio file playing
2. Navigate to audio effects controls
3. Adjust the audio balance slider to favor the left channel
4. Target range: -0.7 to -1.0 (where -1.0 is full left)
5. Settings must persist in VLC configuration

## Real-World Scenario

**Context**: Your right earphone just broke during a long flight, but you need to finish listening to this podcast. You have no spare earphones until you land. Solution: Shift all audio to the working left earphone.

**Alternative scenarios**:
- User with unilateral hearing loss
- Testing mono compatibility in one channel
- Broken audio equipment
- Temporary workaround until replacement

## Expected Results

- Audio balance adjusted to favor left channel (range: -0.7 to -1.0)
- Balance setting persisted in VLC config file
- Audio effects enabled and functional
- Audio audibly shifts to left channel during playback

## Verification Criteria

1. ✅ **VLC Config Accessible**: Configuration file parsed successfully
2. ✅ **Balance Parameter Found**: At least one balance-related key located
3. ✅ **Balance Value Correct**: Value between -0.7 and -1.0 (inclusive)
4. ✅ **Audio Effects Enabled**: Necessary enable flags are set

**Pass Threshold**: 75% (requires correct balance value and persistence evidence)

## Skills Tested

- Audio effects menu navigation (`Tools → Effects and Filters`)
- Spatializer/channel mixer understanding
- Slider manipulation with precision
- Configuration persistence verification
- Understanding of audio balance concepts
- Preference saving and verification

## Controls

- **Menu**: `Tools → Effects and Filters` (or `Ctrl+E`)
- **Tabs**: Navigate to "Audio Effects" → "Spatializer" or "Advanced"
- **Slider**: Adjust balance slider to left (negative values)
- **Preferences**: `Tools → Preferences → Audio` for global settings

## VLC Balance Controls Location

Balance controls may be in different locations depending on VLC version:

1. **Effects and Filters** (Ctrl+E):
   - Audio Effects tab → Spatializer → Balance/Headphone effect
   - Audio Effects tab → Advanced → Stereo mode / Balance

2. **Preferences** (Ctrl+P):
   - Audio → Output modules → Advanced options
   - Audio → Filters → Stereo widener / Channel mixer

## Notes

- VLC balance range: -1.0 (full left) to +1.0 (full right), default 0.0 (center)
- Some VLC versions use different config keys for balance
- Audio effects must be explicitly enabled (checkbox)
- Settings should persist across VLC restarts
- Configuration stored in `~/.config/vlc/vlcrc`

## Common Pitfalls

1. **Not enabling effects**: Moving slider without checking "Enable" box
2. **Wrong tab**: Looking in video effects instead of audio effects
3. **Session-only**: Changes not saved to global preferences
4. **Wrong slider**: Adjusting volume instead of balance
5. **Insufficient adjustment**: Moving slider slightly instead of strongly to left