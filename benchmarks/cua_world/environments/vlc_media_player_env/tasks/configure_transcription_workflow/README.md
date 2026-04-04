# Configure Transcription Workflow Task

**Difficulty**: 🟡 Medium  
**Skills**: Workflow optimization, VLC configuration, preferences navigation  
**Duration**: 90 seconds  
**Steps**: ~35

## Objective

Configure VLC Media Player for efficient transcription workflow by setting up automatic rewind-on-resume behavior. When pausing and resuming playback, VLC should jump back approximately 3 seconds to provide context overlap.

## Real-World Scenario

Maya is a freelance journalist transcribing a 45-minute interview. She needs to configure VLC so that every time she pauses to type and then resumes, the audio automatically rewinds 3 seconds, allowing her to catch any words she missed without manually seeking backward.

This workflow optimization can double transcription productivity by eliminating constant mouse interaction.

## Task Description

The agent must:
1. Open VLC with an audio file (interview/podcast)
2. Navigate to VLC preferences/settings
3. Configure the "short jump" interval to approximately 3 seconds
4. Save the configuration
5. Optionally test the behavior

## Expected Results

- VLC configuration file modified
- Short jump interval set to 2-5 seconds (3 is ideal)
- Configuration persists across VLC sessions

## Verification Criteria

1. ✅ **Config File Exists**: VLC config accessible and valid
2. ✅ **Jump Interval Configured**: Short jump set to 2-5 seconds
3. ✅ **Setting Persisted**: Configuration saved to vlcrc

**Pass Threshold**: 70%

## Skills Tested

- Preferences/settings navigation
- Understanding VLC configuration system
- Workflow optimization thinking
- Configuration persistence verification

## Controls

- **Menu**: Tools → Preferences (Ctrl+P)
- **Show Settings**: Click "All" at bottom left to show advanced settings
- **Navigation**: Interface → Hotkeys → General → Short jump length
- **Alternative**: Configure via hotkeys section

## Notes

The short jump interval in VLC is measured in seconds. Default is typically 10 seconds. For transcription work, 2-5 seconds is optimal - enough context without too much repetition.

Different VLC versions may use slightly different parameter names:
- `short-jump-size`
- `extrashort-jump-size`
- `key-jump-short`