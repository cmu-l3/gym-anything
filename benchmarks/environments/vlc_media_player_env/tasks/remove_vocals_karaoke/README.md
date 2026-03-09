# Remove Vocals for Karaoke Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio effects configuration, filter management  
**Duration**: 90 seconds  
**Steps**: ~25

## Objective

Configure VLC's audio effects to remove or significantly reduce vocals from a music video file, creating a karaoke-suitable playback experience.

## Task Description

The agent must:
1. Open VLC with a music video file playing
2. Navigate to the audio effects menu (Tools → Effects and Filters)
3. Enable an appropriate vocal removal or karaoke-suitable audio filter
4. Verify filter is active and settings persist

## Expected Results

- Audio filter enabled in VLC configuration
- Filter configured to reduce/remove center-channel vocals
- Settings persisted to VLC config file (`vlcrc`)

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Filter Enabled**: Appropriate audio filter is active
3. ✅ **Proper Configuration**: Filter parameters suitable for vocal removal

**Pass Threshold**: 75%

## Skills Tested

- Audio effects menu navigation
- Understanding of audio filters and their purposes
- Configuration persistence verification
- Filter parameter adjustment (advanced)

## Valid Approaches

Multiple audio filters can achieve vocal removal:
- **Karaoke filter** (if available) - Ideal
- **Spatializer** - Very effective for center-channel reduction
- **Stereo Widener** - With center reduction settings
- **Equalizer** - Reducing vocal frequency ranges (200Hz-5kHz)

## Controls

- **Keyboard**: `Ctrl+E` - Open Effects and Filters
- **Menu**: Tools → Effects and Filters → Audio Effects tab
- Enable desired filter checkbox
- Adjust parameters if needed