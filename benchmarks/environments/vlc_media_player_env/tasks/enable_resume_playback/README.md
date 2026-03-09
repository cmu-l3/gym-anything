# Enable Resume Playback Task

**Difficulty**: 🟢 Easy  
**Skills**: Configuration management, preferences navigation, feature verification  
**Duration**: 120 seconds  
**Steps**: ~40

## Objective

Configure VLC Media Player to automatically save and resume playback positions when videos are closed and reopened. This addresses a common user frustration of having to manually seek back to the last watched position.

## Task Description

The agent must:
1. VLC launches with default settings (resume disabled)
2. Navigate to VLC preferences
3. Enable the "Continue playback?" or resume playback feature
4. Optionally test the feature by:
   - Playing a video to a specific point
   - Closing VLC
   - Reopening the video
   - Verifying it resumes from the last position

## Expected Results

- VLC preferences configured with resume playback enabled
- Setting persists in VLC configuration (`qt-continue=1` or `qt-continue=2`)
- Feature works correctly when tested

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Resume Enabled**: Resume setting enabled in config (qt-continue ≥ 1)
3. ✅ **Functional Test** (Optional): Evidence of successful resume test

**Pass Threshold**: 70%

## Skills Tested

- Preferences/Settings navigation (Tools → Preferences)
- Interface settings configuration
- Understanding of session persistence
- Feature testing and verification

## Controls

- **Menu**: Tools → Preferences (or Ctrl+P)
- **Interface settings**: "Ask to resume playback" or "Continue playback"
- **Settings modes**: Simple vs. Advanced (use Simple for this task)

## Notes

The resume feature in VLC is controlled by the `qt-continue` setting:
- `0` = Never resume (disabled)
- `1` = Ask to resume (prompt dialog)
- `2` = Always resume (automatic)

Either `1` or `2` is acceptable for this task.