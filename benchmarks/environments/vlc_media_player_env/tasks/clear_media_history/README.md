# Clear Media History Task

**Difficulty**: 🟡 Low-Medium  
**Skills**: Privacy settings navigation, configuration management  
**Duration**: 60 seconds  
**Steps**: ~15

## Objective

Clear VLC's recently played media history to protect privacy before sharing your device.

## Task Description

The agent must:
1. VLC launches with several videos in recent history
2. Navigate to Tools → Preferences (Ctrl+P)
3. Find and clear the recent media items
4. Save the changes
5. Verify recent items list is empty

## Expected Results

- Recent media menu (Media → Open Recent) is empty
- VLC config file has no recent items
- Privacy setting optionally disabled for future tracking

## Verification Criteria

1. ✅ **Config File Clean**: No recent items in vlc-qt-interface.conf
2. ✅ **History Cleared**: Recent items count is zero
3. ✅ **Config Modified**: Settings were saved during task

**Pass Threshold**: 70%

## Skills Tested

- Privacy awareness
- Preferences menu navigation
- Settings search and identification
- Understanding of data persistence
- Configuration management

## Real-World Context

**Scenario**: You're about to lend your laptop to a classmate for a group project. You've been watching personal videos on VLC and don't want them to see your viewing history in the "Open Recent" menu. You need to quickly clear this history while keeping your other VLC preferences intact.

## Controls

- **Keyboard**: `Ctrl+P` - Open Preferences
- **Menu**: Tools → Preferences → Privacy/Network → Clear
- **Alternative**: Media → Open Recent → Clear (simpler but less comprehensive)