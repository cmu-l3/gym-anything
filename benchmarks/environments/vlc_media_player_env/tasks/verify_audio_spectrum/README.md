# Verify Audio Spectrum Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio visualization, spectrum analysis, quality verification  
**Duration**: 120 seconds  
**Steps**: ~25

## Objective

Enable VLC's spectrum analyzer visualization to verify audio quality claims and detect potentially fake lossless audio files.

## Task Description

The agent must:
1. Open VLC Media Player
2. Enable audio spectrum visualization (spectrometer mode)
3. Open and play the suspicious audio file
4. Observe the frequency spectrum to assess audio quality

## Scenario

You have a suspicious audio file (`questionable_hifi.flac`) that claims to be high-resolution 96kHz/24-bit lossless audio. Use VLC's spectrum analyzer to verify whether it actually contains high-frequency content above 20kHz, or if it's likely an upsampled lossy file.

## Expected Results

- VLC audio visualizer enabled and set to spectrum/spectrometer mode
- Audio file played in VLC
- Visualizer configuration persisted in VLC settings

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Visualizer Enabled**: Audio visualizer is active
3. ✅ **Spectrum Mode**: Visualizer type is spectrum/spectrometer
4. ✅ **File Played**: Target audio file was opened in VLC

**Pass Threshold**: 70%

## Skills Tested

- Audio effects/visualizer menu navigation
- Understanding of audio visualization tools
- File opening and playback
- Settings persistence
- Audio quality analysis concepts

## Controls

- **Menu**: Tools → Effects and Filters → Visualizations
- **Or**: Tools → Preferences → Audio → Visualizations
- **Keyboard**: `Ctrl+E` to open effects dialog
- **File**: Media → Open File (Ctrl+O)

## Real-World Application

Audiophiles and consumers use this technique to verify if "lossless" audio purchases are genuine or upsampled lossy files. Real high-resolution audio shows frequency content up to the Nyquist frequency (48kHz for 96kHz sample rate), while fake files show a sharp cutoff around 16-20kHz.