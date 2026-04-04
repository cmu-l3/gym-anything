# Clear Playback History Task

**Difficulty**: 🟡 Easy-Medium  
**Skills**: Privacy management, settings navigation, configuration understanding  
**Duration**: 60 seconds  
**Steps**: ~25

## Objective

Clear all VLC playback history for privacy purposes, including recent files list and media library history. This simulates the real-world scenario of clearing viewing history before returning a borrowed device.

## Task Description

The agent must:
1. VLC has been used to watch several media files
2. Clear the "Open Recent Media" list
3. Clear Media Library history
4. Ensure VLC configuration shows no trace of previously played files

## Expected Results

- Recent files list is empty (vlcrc shows no recent-items)
- Media Library is cleared (ml.xspf has no tracks)
- Privacy restored - no trace of viewing history

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file can be read
2. ✅ **Recent Files Cleared**: No recent-items in vlcrc
3. ✅ **Media Library Cleared**: ml.xspf has no track entries

**Pass Threshold**: 70%

## Skills Tested

- Settings/preferences navigation
- Understanding where applications store data
- Privacy awareness
- File-based configuration understanding
- Menu navigation (Media → Open Recent → Clear)

## Real-World Context

**Scenario**: You borrowed a friend's laptop for a flight and watched some movies using VLC. Before returning the laptop, you want to clear your viewing history out of courtesy.

**Why this matters**:
- Privacy on shared/borrowed devices
- Workplace computers with mixed usage
- Before selling or lending a device
- General digital hygiene

## Controls

- **GUI Method**: Media → Open Recent Media → Clear (at bottom of menu)
- **Tools Method**: Tools → Preferences → Reset (advanced)
- **File Method**: Directly edit config files (advanced users)

## Notes

VLC stores recent files in multiple locations:
- Config file: `~/.config/vlc/vlcrc` (recent-items entries)
- Media Library: `~/.local/share/vlc/ml.xspf` (playback history)

Both must be cleared for complete privacy.