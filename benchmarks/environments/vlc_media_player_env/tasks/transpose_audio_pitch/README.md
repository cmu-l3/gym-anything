# Transpose Audio Pitch Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio effects, pitch manipulation, effects panel navigation  
**Duration**: 60 seconds  
**Steps**: ~30

## Objective

Configure VLC to transpose the audio pitch of a music file down by 3 semitones while maintaining the original playback speed, simulating a karaoke/vocal practice scenario.

## Task Description

**Scenario**: You've downloaded a karaoke track that's too high for your vocal range. You need to lower the pitch by 3 semitones (from E major to C major) without changing the tempo, so you can practice singing along comfortably.

The agent must:
1. VLC launches with an audio track playing
2. Open the audio effects panel (Tools → Effects and Filters)
3. Enable audio effects and navigate to the pitch adjustment
4. Set pitch shift to -3 semitones (or -300 cents)
5. Ensure playback speed remains at 1.0x
6. Settings persist in VLC configuration

## Expected Results

- Audio effects filter enabled in VLC
- Pitch shift set to -3 semitones (tolerance: ±0.5 semitones)
- Playback speed unchanged (1.0x)
- Configuration saved to vlcrc

## Verification Criteria

1. ✅ **Audio Filter Enabled**: Audio effects filter active in config
2. ✅ **Correct Pitch Value**: Pitch shift within -2.5 to -3.5 semitones
3. ✅ **Speed Unchanged**: Playback speed at 1.0x

**Pass Threshold**: 70%

## Skills Tested

- Audio effects menu navigation
- Understanding pitch vs. speed/tempo
- Slider/numeric input adjustment
- Effects configuration persistence
- Real-world audio manipulation workflow

## Controls

- **Menu**: Tools → Effects and Filters (Ctrl+E)
- **Audio Effects Tab**: Select and enable effects
- **Pitch slider**: Adjust semitone offset (-12 to +12)
- **Checkbox**: Enable "Audio Effects" to activate

## Notes

- VLC's pitch shifting uses the scaletempo filter or audio pitch adjustment
- Pitch is typically stored in semitones (12 per octave) or cents (100 per semitone)
- Don't confuse with playback speed (which affects both pitch and tempo)
- This is commonly used for karaoke, music practice, and accessibility