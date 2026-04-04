# Setup Practice Loop Task

**Difficulty**: 🟡 Medium  
**Skills**: A-B repeat configuration, playback speed control, pitch preservation  
**Duration**: 90-120 seconds  
**Steps**: ~40

## Objective

Configure VLC to create a practice loop for musicians learning a guitar solo. Set up A-B repeat for a specific section, slow down playback to 70%, and enable pitch preservation.

## Task Description

The agent must:
1. Open VLC with a practice song (3 minutes, solo from 1:34 to 1:58)
2. Navigate to the solo start position (~1:34 / 94 seconds)
3. Set A-B repeat loop for the solo section (1:34 to 1:58)
4. Adjust playback speed to 0.70x (70% of normal speed)
5. Enable time-stretching to preserve pitch at slower speed
6. Verify the loop plays continuously at reduced speed with normal pitch

## Expected Results

- A-B repeat loop configured for timestamps ~94s to ~118s
- Playback speed set to 0.70 (±0.05 tolerance)
- Time-stretching (pitch preservation) enabled in config
- Settings persist in VLC configuration files

## Verification Criteria

1. ✅ **Playback Speed Configured**: Speed set to 0.70 (±0.05)
2. ✅ **Time-Stretching Enabled**: Pitch preservation active
3. ✅ **A-B Loop Indicator**: Evidence of A-B repeat usage

**Pass Threshold**: 67% (2/3 criteria must pass)

## Skills Tested

- A-B repeat loop setup (Playback → A-B Repeat)
- Timeline navigation and precise seeking
- Playback speed adjustment (Playback → Speed)
- Audio effects configuration (time-stretching)
- Understanding of pitch vs. tempo
- Multiple feature integration

## Controls

### A-B Repeat
- **Menu**: Playback → A-B Repeat → Set A / Set B
- **Toolbar**: Click A-B button if visible

### Playback Speed
- **Menu**: Playback → Speed → Slower / Faster / Custom
- **Keyboard**: `[` to slow down, `]` to speed up
- **Target**: 0.70x (press `[` three times from normal speed)

### Time Stretching
- **Menu**: Tools → Preferences → Show Settings: All → Audio → Enable time-stretching audio
- **Or**: Tools → Preferences → Audio → Enable time-stretching audio

## Notes

- The practice song is 3 minutes long with a distinctive solo section from 1:34-1:58
- Solo section has higher frequency content (880Hz+) vs. main song (440Hz)
- Without time-stretching, slowed audio sounds unnaturally low-pitched
- A-B repeat state may not fully persist in config; speed and time-stretch must be correct