# Enhance Recording Clarity Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio enhancement, filter application, audio export  
**Duration**: 180 seconds  
**Steps**: ~50

## Objective

Enhance a noisy audio recording to improve speech intelligibility using VLC's audio processing capabilities (compressor, equalizer, and audio filters).

## Scenario

A citizen journalist received an audio tip recorded covertly in noisy outdoor conditions. The recording contains important information about environmental issues, but speech is barely intelligible due to wind noise, traffic sounds, and inconsistent volume. Your task is to use VLC's audio enhancement features to make the speech clear enough for transcription.

## Task Description

The agent must:
1. Open the noisy audio file at `/home/ga/Music/noisy_recording.mp3`
2. Apply audio filters to enhance speech clarity:
   - **Compressor/Limiter** to normalize volume variations
   - **Equalizer** to boost speech frequencies and reduce rumble
3. Export/convert the enhanced audio to `/home/ga/Music/enhanced_recording.mp3`

## Expected Results

- Enhanced audio file created at specified path
- File duration matches original (±2 seconds)
- Audio shows improved characteristics:
  - Increased mean volume (compression applied)
  - Better RMS level (signal strengthened)
  - Reduced low-frequency content

## Verification Criteria

1. ✅ **File Exists**: Enhanced audio file found at correct path
2. ✅ **Duration Valid**: Duration matches original recording
3. ✅ **Volume Boosted**: Mean volume increased by at least 3dB
4. ✅ **Signal Improved**: RMS level shows improvement
5. ✅ **File Quality**: Reasonable file size and properties

**Pass Threshold**: 60%

## Skills Tested

- Audio effects menu navigation (Tools → Effects and Filters)
- Compressor configuration for dynamic range control
- Equalizer adjustment for frequency shaping
- Media conversion with effects applied
- Understanding audio enhancement concepts

## Controls

- **Menu**: Tools → Effects and Filters (Ctrl+E)
- **Audio Effects Tab**: 
  - Compressor: Adjust ratio and threshold
  - Equalizer: Enable and adjust frequency bands
- **Convert/Save**: Media → Convert/Save (Ctrl+R)

## Real-World Context

This task simulates real scenarios where:
- Journalists need to transcribe covert recordings
- Legal professionals enhance evidence audio
- Researchers clarify poor-quality field interviews
- Users recover important but degraded recordings

## Notes

Audio enhancement requires balancing noise reduction with speech preservation. Over-processing can introduce artifacts. The goal is improved intelligibility, not perfect audio.