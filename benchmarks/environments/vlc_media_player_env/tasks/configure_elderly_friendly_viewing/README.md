# Configure Elderly-Friendly Viewing Task

**Difficulty**: 🟡 Medium  
**Skills**: Accessibility configuration, user-centered design, settings persistence  
**Duration**: 120 seconds  
**Steps**: ~40

## Objective

Configure VLC Media Player for elderly-friendly viewing by adjusting subtitle size, audio normalization, interface simplification, and disabling confusing prompts.

## Task Description

**Scenario**: Your elderly mother (78) struggles with VLC because subtitles are too small, volume varies wildly between videos, dialogue is hard to hear, and she gets confused by interface prompts.

The agent must:
1. Increase subtitle font size dramatically (≥3x default)
2. Enable audio normalization to prevent volume jumps
3. Enable audio compression (night mode) for clearer dialogue
4. Simplify the interface to reduce confusion
5. Set high-contrast subtitles for visibility
6. Disable automatic update prompts

## Expected Results

- VLC configured with elderly-friendly settings in `vlcrc`:
  - Subtitle font size ≥72pt or relative size ≥40
  - Bold subtitles enabled
  - Audio normalization enabled
  - Audio compression enabled
  - Interface simplified
  - Prompts disabled
- Settings persist across VLC restarts

## Verification Criteria

1. ✅ **Subtitle Size**: Font ≥72pt or relative ≥40
2. ✅ **Subtitle Styling**: Bold enabled
3. ✅ **Audio Normalization**: Enabled
4. ✅ **Audio Compression**: Enabled for dialogue clarity
5. ✅ **Interface Simplified**: Minimal view or privacy prompts disabled
6. ✅ **Prompts Disabled**: Update notifications off

**Pass Threshold**: 4/6 criteria (67%)

## Skills Tested

- Preferences menu navigation (Tools → Preferences → Show All)
- Understanding accessibility needs
- Multi-category configuration (subtitles, audio, interface)
- Settings persistence verification
- User-centered design thinking

## Configuration Paths

- **Subtitle Font**: Preferences → Video → Subtitles/OSD → Text renderer → Font size
- **Audio Normalization**: Preferences → Audio → Volume normalization / ReplayGain
- **Audio Compression**: Preferences → Audio → Compressor
- **Interface**: Preferences → Interface → Qt → Minimal view
- **Prompts**: Preferences → Interface → Privacy interaction

## Notes

This task simulates real-world caregiving scenarios where technology must be configured for users with vision, hearing, and cognitive accessibility needs. The agent must think holistically about the elderly user experience, not just individual features.