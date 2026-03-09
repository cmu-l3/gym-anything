# Reduce Tape Hiss Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio effects, noise reduction, filter configuration  
**Duration**: 180 seconds  
**Steps**: ~50

## Objective

Apply VLC's audio filtering to reduce tape hiss/static in a digitized audio recording from an old cassette tape, configure noise reduction settings appropriately, and ensure settings persist.

## Task Description

The agent must:
1. VLC launches with a noisy audio file (digitized cassette tape)
2. Navigate to audio effects menu (Tools → Effects and Filters)
3. Enable and configure audio filters for noise reduction
4. Apply appropriate settings (compressor, normalizer, or other filters)
5. Configuration persists in VLC settings

## Expected Results

- Audio filters enabled in VLC configuration
- At least one noise reduction filter active
- Settings saved to vlcrc configuration file

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Filter Enabled**: Audio filter is enabled in configuration
3. ✅ **Noise Reduction Active**: Appropriate filters configured

**Pass Threshold**: 70%

## Skills Tested

- Audio effects menu navigation
- Understanding of audio filtering concepts
- Filter parameter adjustment
- Settings persistence verification
- Real-world audio restoration workflow

## Scenario Context

Elena has digitized cassette tapes from her grandmother's 80th birthday party (1995). The audio has significant tape hiss that makes voices hard to understand. She needs to reduce the hiss before sharing with family.

## Controls

- **Menu**: Tools → Effects and Filters (Ctrl+E)
- **Audio Effects tab**: Enable filters like:
  - Dynamic range compressor (reduces background noise)
  - Volume normalizer
  - Spatializer
  - Parametric equalizer
- **Sliders**: Adjust filter parameters

## Notes

VLC's audio filters work in real-time during playback. The goal is to reduce constant background hiss while preserving speech clarity. Over-filtering can make audio sound muffled.