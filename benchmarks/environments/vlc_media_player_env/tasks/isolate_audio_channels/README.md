# Isolate Audio Channels Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio configuration, channel isolation, troubleshooting  
**Duration**: 180 seconds  
**Steps**: ~40

## Objective

Configure VLC to isolate and play only the front-right audio channel from a 5.1 surround sound test file, enabling systematic troubleshooting of speaker connections.

## Task Description

The agent must:
1. Open VLC with a 5.1 surround sound test audio file
2. Navigate to audio effects/filters
3. Configure channel isolation to play ONLY front-right channel
4. Mute/disable all other channels (front-left, center, rear-left, rear-right, LFE)
5. Document findings in a test results log

## Scenario

You've just set up a 5.1 surround sound system but suspect the speakers might be miswired. You need to methodically test each channel individually to verify which physical speaker corresponds to each audio channel. This task focuses on isolating the front-right channel first.

## Expected Results

- VLC configured with audio filters for channel isolation
- Only front-right channel audible during playback
- Test results documented in `/home/ga/Documents/channel_test_results.txt`
- VLC configuration persisted

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file exists and is parseable
2. ✅ **Channel Filter Applied**: Audio filter or stereo-mode configured for channel isolation
3. ✅ **Documentation Created**: Test results log exists with relevant information

**Pass Threshold**: 60%

## Skills Tested

- Audio effects menu navigation
- Understanding of multi-channel audio concepts
- Filter/effects configuration
- Systematic troubleshooting methodology
- Documentation skills

## Controls

- **Menu**: Audio → Audio Device / Audio Effects
- **Menu**: Tools → Effects and Filters → Audio Effects
- **Keyboard**: `Ctrl+E` - Open effects dialog
- **Audio filters**: Channel mixer, Stereo widener, Headphone channel mixer

## Approaches

Multiple valid approaches:
1. Use stereo-mode settings (Audio menu)
2. Use audio filters with channel remapping
3. Use headphone channel mixer effects
4. Use audio device/output configuration

## Notes

VLC provides several ways to manipulate audio channels. The key is to configure the player so that only one specific channel (front-right) is audible while others are muted or disabled.