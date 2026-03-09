# Isolate Bass Frequencies Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio effects, equalizer configuration, frequency understanding  
**Duration**: 120 seconds  
**Steps**: ~25

## Objective

Configure VLC's audio equalizer to isolate and enhance bass frequencies for music practice. This simulates a real-world scenario where a musician needs to hear a bass line more clearly in a dense mix.

## Task Description

The agent must:
1. VLC launches with a music track playing
2. Navigate to Tools → Effects and Filters → Audio Effects → Equalizer
3. Enable the equalizer checkbox
4. Boost bass frequencies (60Hz, 170Hz, 310Hz) by +8 to +12 dB
5. Reduce mid-range frequencies (600Hz, 1kHz, 3kHz) by -3 to -6 dB
6. Settings persist in VLC configuration

## Expected Results

- Equalizer enabled in VLC config
- Bass frequencies (60-310 Hz) boosted significantly
- Mid frequencies (600Hz-3kHz) reduced to minimize interference
- EQ curve shows clear bass isolation pattern

## Verification Criteria

1. ✅ **Equalizer Enabled**: equalizer-preamp exists in config
2. ✅ **Bass Boost**: First 3 frequency bands boosted ≥+6 dB
3. ✅ **Mid Reduction**: Bands 4-6 show negative values (reduction)
4. ✅ **Pattern Match**: Bass bands significantly higher than mid bands

**Pass Threshold**: 70%

## Skills Tested

- Multi-level menu navigation (Tools → Effects → Equalizer)
- Checkbox/toggle control
- Slider manipulation for multiple frequency bands
- Understanding audio frequency ranges
- Configuration persistence verification

## Controls

- **Menu**: Tools → Effects and Filters (or Ctrl+E)
- **Equalizer Tab**: Audio Effects → Equalizer
- **Enable Checkbox**: Must be checked for settings to apply
- **Sliders**: Adjust 10 frequency bands (60Hz to 16kHz)
- **Preamp**: Optional adjustment to prevent clipping

## Frequency Bands

VLC's 10-band equalizer covers:
- **60 Hz** - Deep bass (boost for bass isolation)
- **170 Hz** - Bass fundamentals (boost)
- **310 Hz** - Upper bass (moderate boost)
- **600 Hz** - Low mids (reduce to clear bass)
- **1 kHz** - Mids (reduce)
- **3 kHz** - Upper mids (reduce)
- **6 kHz** - Presence (leave neutral or slight reduction)
- **12 kHz, 14 kHz, 16 kHz** - Treble (leave neutral)

## Real-World Context

Musicians learning bass lines by ear often struggle to hear bass in dense mixes. By boosting low frequencies (60-310 Hz) and reducing competing mid frequencies (600Hz-3kHz), the bass becomes much more audible without specialized software.