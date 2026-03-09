# Practice Music Transcription Task

**Difficulty**: 🟡 Medium  
**Skills**: Time-stretching audio, playback speed control, audio effects  
**Duration**: 90 seconds  
**Steps**: ~35

## Objective

Configure VLC's time-stretching playback for music transcription by slowing audio to 60% speed while preserving the original pitch, enabling musicians to learn complex musical passages note-by-note.

## Task Description

**Scenario**: A music student needs to learn a fast jazz solo by slowing it down to 60% speed (0.6x) while maintaining the original pitch. Without pitch preservation, the audio would sound distorted and unusable for transcription.

The agent must:
1. VLC launches with a jazz audio file
2. Enable time-stretching audio filter (preserves pitch)
3. Adjust playback speed to 0.60x (60%)
4. Configuration persists in VLC settings

## Expected Results

- Playback speed set to 0.60x (±0.05 tolerance)
- Time-stretching filter enabled (`scaletempo` or `scaletempo2`)
- Audio plays slower but maintains original pitch/key
- Settings saved to VLC configuration file

## Verification Criteria

1. ✅ **Speed Configured**: Playback speed set to 0.60x (±0.05 tolerance)
2. ✅ **Time-Stretch Enabled**: `scaletempo` filter is active (pitch preserved)
3. ✅ **Config Persisted**: Settings saved to VLC configuration file
4. ✅ **Not Pitch-Shifted**: Time-stretching maintains pitch (not just rate change)
5. ✅ **Practically Usable**: Speed is appropriate for transcription (0.4-0.8 range)

**Pass Threshold**: 75% (4/5 criteria)

## Skills Tested

- Audio effects navigation (Tools → Effects and Filters)
- Time-stretching vs. pitch-shifting understanding
- Playback speed controls
- Configuration persistence
- Multi-step coordination (filter + speed)

## Controls

- **Menu**: Tools → Effects and Filters (Ctrl+E)
- **Audio Effects Tab**: Advanced → Time stretching
- **Playback Speed**:
  - `[` (left bracket): Slower
  - `]` (right bracket): Faster
  - Playback → Speed menu
- **Keyboard**: Press `[` multiple times to reach ~0.60x

## Notes

VLC's time-stretching uses the `scaletempo` or `scaletempo2` filter to preserve pitch when changing playback speed. Without this filter enabled, speed changes also alter pitch (chipmunk/monster effect), which is unusable for music transcription.

The filter must be enabled BEFORE or AFTER changing speed - the order doesn't matter, but both actions are required.