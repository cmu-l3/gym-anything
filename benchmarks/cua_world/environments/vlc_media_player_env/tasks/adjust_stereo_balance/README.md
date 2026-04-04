# Adjust Stereo Balance Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio effects navigation, accessibility configuration, settings persistence  
**Duration**: 90-120 seconds  
**Steps**: ~40

## Objective

Configure VLC Media Player to shift stereo audio balance significantly toward the right channel for accessibility purposes (asymmetric hearing loss or damaged left audio hardware).

## Real-World Scenario

Users with hearing loss in one ear or damaged headphones/speakers need to shift audio balance to their stronger ear/working speaker. This is a common accessibility need that requires finding non-obvious audio effect controls.

## Task Description

The agent must:
1. VLC launches with an audiobook sample playing
2. Access audio effects/filters menu
3. Configure audio settings to emphasize right channel
4. Ensure settings persist in VLC configuration

## Expected Results

- Audio balance shifted significantly to right (≥ 60% emphasis)
- Audio effects filter enabled in VLC config
- Settings persisted in vlcrc configuration file
- Audio effects active and verifiable

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Audio Effects Enabled**: Audio filter/effects are active
3. ✅ **Balance Modified**: Stereo balance or spatializer settings show right-channel emphasis

**Pass Threshold**: 70%

## Skills Tested

- Audio effects menu navigation (Tools → Effects and Filters)
- Understanding of audio accessibility features
- Settings persistence verification
- Non-obvious UI element discovery

## Controls

- **Menu**: Tools → Effects and Filters (Ctrl+E)
- **Audio Effects tab**: Spatializer, Equalizer, or Advanced
- **Preferences**: Show All → Audio for advanced settings
- **Alternative**: Tools → Preferences → Audio → Effects

## Implementation Notes

VLC doesn't have a simple "balance" slider in the main interface. Users must use:
- **Spatializer effect** with adjusted parameters
- **Audio filter modules** with channel emphasis
- **Advanced preferences** for low-level audio configuration

The most practical approach is through **Audio Effects → Spatializer** or enabling custom audio filters that affect channel balance.