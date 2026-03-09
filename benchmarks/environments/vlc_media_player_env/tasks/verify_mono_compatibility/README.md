# Verify Mono Compatibility Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio configuration, output routing, quality assessment  
**Duration**: 90 seconds  
**Steps**: ~40

## Objective

Configure VLC Media Player to downmix stereo audio to mono output for podcast mobile compatibility testing.

## Task Description

**Real-World Context**: You are a podcast producer who needs to verify that your audio mix is compatible with mono playback before publishing. Many listeners will hear your content on phones, smart speakers, or other mono/limited-stereo devices. You need to configure VLC to play the audio in mono mode and verify the configuration is correctly applied.

The agent must:
1. Open VLC with a stereo podcast audio file
2. Navigate to VLC's audio settings
3. Enable mono downmix/mono output
4. Verify the setting persists in VLC configuration

## Expected Results

- VLC configured to output audio in mono (not stereo)
- Mono setting saved to VLC configuration file
- Audio can be tested for mono compatibility

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Mono Enabled**: Mono downmix setting is active
3. ✅ **Correct Method**: Proper audio filter/output method used

**Pass Threshold**: 70%

## Skills Tested

- Audio settings navigation (Tools → Preferences → Audio)
- Understanding of mono vs. stereo audio concepts
- Advanced settings configuration
- Professional audio quality control workflow

## Controls

- **Menu**: Tools → Preferences (Ctrl+P)
- **Advanced Settings**: "Show settings: All" at bottom left
- **Audio Section**: Navigate to Audio → Filters or Audio → Output
- **Mono Filter**: Enable "Mono" audio filter checkbox

## Notes

VLC can enable mono output through several methods:
- Audio filters (recommended): `audio-filter=mono`
- Channel mixer: Set to mono mode
- Output channels: Configure for mono output

The verification checks for any valid mono configuration method.