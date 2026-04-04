# Resume Position Recovery Task

**Difficulty**: 🟡 Medium  
**Skills**: Settings configuration, playback position management, media library understanding  
**Duration**: 90 seconds  
**Steps**: ~50

## Objective

Configure VLC Media Player to automatically remember and resume playback position for a long-form documentary video, then verify the resume functionality works correctly across VLC sessions.

## Real-World Context

You're researching a 90-minute documentary for a university paper. You've been taking notes and are 47 minutes into the video when your laptop battery dies. When you restart, you need to resume from exactly where you left off—not manually scrubbing through 47 minutes trying to find "that part about the transportation system."

This solves the common frustration of losing your place in long videos across viewing sessions.

## Task Description

The agent must:
1. Enable VLC's "Continue playback?" feature for resuming media
2. Open the documentary video
3. Navigate to approximately 47 minutes (±30 seconds)
4. Close VLC properly to save the position
5. Verify settings were configured correctly

## Expected Results

- VLC configured to enable resume playback (qt-continue = 0 or 1)
- Documentary advanced to ~47:00 position
- Playback position saved in VLC's media library
- Resume functionality would work on next launch

## Verification Criteria

1. ✅ **Resume Enabled**: VLC configured to support resume (qt-continue ≠ 2)
2. ✅ **Position Saved**: Media library contains playback position
3. ✅ **Correct Position**: Position is 46:30-47:30 (target: 47:00)

**Pass Threshold**: 70%

## Skills Tested

- VLC preferences/settings navigation
- Understanding resume playback feature
- Precise timestamp seeking
- Media library concepts
- Configuration file management

## Controls

- **Settings**: Tools → Preferences → Interface → "Continue playback?"
- **Seek**: Click progress bar, or keyboard shortcuts
  - `Shift+Right`: Jump forward 5s
  - `Ctrl+Right`: Jump forward 1 min
  - Go → Jump to Time: Direct time entry
- **Close**: `Ctrl+Q` to properly close VLC

## Notes

The documentary is 90 minutes long. Use seeking controls to quickly navigate to 47:00 rather than playing through. VLC saves playback position when properly closed.