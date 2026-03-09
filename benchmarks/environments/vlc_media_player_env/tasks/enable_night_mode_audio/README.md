# Enable Night Mode Audio Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio effects configuration, dynamic range compression, VLC preferences persistence  
**Duration**: 90-120 seconds  
**Steps**: ~40

## Objective

Enable VLC's audio compression and normalization features to create "night mode" audio that reduces loud sounds and boosts quiet sounds, making late-night viewing comfortable.

## Task Description

The agent must:
1. Open VLC with a test video that has extreme dynamic range
2. Navigate to audio effects (Tools → Effects and Filters)
3. Enable the Dynamic Range Compressor
4. Enable the Volume Normalizer/Audio Normalizer
5. Make settings persistent by saving in Preferences

## Real-World Scenario

**Context:** It's 11 PM and you want to watch an action movie in your apartment. The movie has whisper-quiet dialogue but ear-shattering explosions. You need to compress the audio dynamic range so loud parts don't disturb neighbors while quiet dialogue remains audible.

## Expected Results

- Dynamic range compressor enabled in VLC audio filters
- Volume normalizer enabled in VLC audio filters
- Settings saved persistently in vlcrc configuration file

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Compressor Enabled**: Dynamic range compressor filter active
3. ✅ **Normalizer Enabled**: Volume normalizer filter active

**Pass Threshold**: 70%

## Skills Tested

- Audio effects menu navigation
- Understanding audio dynamics concepts
- Multi-step configuration workflow
- Preferences management
- Settings persistence

## Controls

- **Menu**: Tools → Effects and Filters (Ctrl+E)
- **Audio Effects Tab**: Enable compressor and normalizer
- **Preferences**: Tools → Preferences → Audio → Filters
- **Save**: Click Save button to persist settings

## Notes

This task tests the agent's ability to:
- Navigate nested dialogs (Effects window + Preferences)
- Enable multiple related features
- Understand the importance of saving settings
- Solve a real-world audio problem