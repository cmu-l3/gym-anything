# Adjust Pitch Without Tempo Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio effects, pitch adjustment, music practice tools  
**Duration**: 120 seconds  
**Steps**: ~35

## Objective

Configure VLC to shift the pitch of an audio file by +1 semitone (100 cents) without affecting playback speed, enabling musicians to practice along with recordings in different tunings.

## Task Description

The agent must:
1. Open an audio file in VLC
2. Navigate to audio effects settings (Tools → Effects and Filters)
3. Enable pitch adjustment filter
4. Set pitch shift to +1 semitone (+100 cents)
5. Ensure tempo/speed remains unchanged (1.0x)

## Expected Results

- Pitch adjustment audio filter enabled in VLC
- Pitch shift value set to +1 semitone
- Playback speed remains at normal rate (1.0x)
- Settings persisted in VLC configuration

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Filter Enabled**: Pitch adjustment filter active
3. ✅ **Correct Pitch Value**: Pitch shift ≈ +1 semitone (±10 cents tolerance)
4. ✅ **Tempo Preserved**: Playback speed unchanged (1.0x)

**Pass Threshold**: 70%

## Skills Tested

- Effects dialog navigation (Ctrl+E)
- Audio effects understanding
- Pitch vs. tempo distinction
- Filter enablement
- Slider/value adjustment
- Settings persistence

## Controls

- **Menu**: Tools → Effects and Filters (Ctrl+E)
- **Audio Effects tab**: Select "Pitch shifter" or similar
- **Enable checkbox**: Activate the filter
- **Slider/Input**: Adjust pitch shift value

## Real-World Context

Musicians often need to transpose audio to match different instrument tunings. For example, many 1990s rock songs were recorded with guitars tuned half-step down (E♭ standard). Using pitch shift without tempo change allows practicing along with these recordings without constantly retuning instruments.

## Notes

- Pitch shift is typically measured in semitones (1 semitone = 100 cents)
- VLC may represent this as semitones, cents, or frequency ratio (1.0594631 for +1 semitone)
- This is different from playback speed control, which changes both pitch AND tempo together