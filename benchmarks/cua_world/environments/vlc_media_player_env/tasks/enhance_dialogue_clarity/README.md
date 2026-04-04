# Enhance Dialogue Clarity Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio effects configuration, settings navigation, accessibility  
**Duration**: 90 seconds  
**Steps**: ~35

## Objective

Configure VLC's audio processing features to enhance dialogue intelligibility for viewing in noisy environments (trains, cafes, gyms). Enable dynamic range compression and volume normalization to make quiet dialogue audible without raising volume to dangerous levels.

## Task Description

The agent must:
1. Open VLC with a video playing
2. Navigate to audio effects settings (Tools → Effects and Filters → Audio Effects)
3. Enable the Compressor effect with appropriate settings
4. Enable Volume Normalization
5. Optionally adjust equalizer to boost speech frequencies
6. Ensure settings persist in VLC configuration

## Expected Results

- Compressor enabled in VLC config with ratio ≥ 4.0
- Volume normalization enabled
- Audio filters active and saved to vlcrc
- Settings persist across VLC sessions

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Audio Filters Enabled**: audio-filter key exists and non-empty
3. ✅ **Compressor Active**: Compressor in audio filter chain
4. ✅ **Compressor Configured**: Compression ratio ≥ 4.0
5. ✅ **Normalization Active**: Volume normalization enabled
6. ✅ **Safe Levels**: Volume not set to dangerous levels

**Pass Threshold**: 67% (4/6 criteria)

## Skills Tested

- Advanced audio settings navigation
- Understanding of audio compression concepts
- Multi-effect configuration
- Settings persistence
- Accessibility feature usage

## Controls

- **Menu**: Tools → Effects and Filters (Ctrl+E)
- **Audio Effects tab**: Compressor, Spatializer, Equalizer
- **Compressor settings**: RMS/peak, Attack, Release, Threshold, Ratio, Knee, Makeup gain
- **Checkbox**: Enable audio volume normalization

## Real-World Context

A commuter is trying to watch their favorite show on a noisy train. Dialogue is nearly inaudible even at max volume, but action scenes and music are too loud. They need to configure VLC's audio processing to compress the dynamic range and normalize volume, making quiet dialogue audible without making loud sounds painful.

## Notes

- Dynamic range compression reduces the difference between loud and quiet sounds
- Volume normalization prevents sudden volume changes
- Mid-range EQ boost (500Hz-4kHz) specifically enhances speech clarity
- Settings are saved to `/home/ga/.config/vlc/vlcrc`