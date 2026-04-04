# Configure Screenshot Hotkey Task

**Difficulty**: 🟡 Medium  
**Skills**: Preferences navigation, hotkey customization, workflow optimization  
**Duration**: 120 seconds  
**Steps**: ~35

## Objective

Customize VLC's screenshot/snapshot hotkey from the default binding to a more convenient key combination using VLC's preferences system.

## Task Description

The agent must:
1. Open VLC's preferences dialog
2. Navigate to advanced preferences (Show All settings)
3. Locate the hotkeys settings section
4. Find the snapshot/screenshot hotkey binding
5. Change it to a more convenient key (e.g., F8, Ctrl+P)
6. Save the preferences

## Expected Results

- Hotkey configuration changed from default (Shift+S)
- New hotkey saved in VLC config file (`vlcrc`)
- New binding is valid and well-formatted

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Hotkey Changed**: Snapshot hotkey differs from default
3. ✅ **Valid Format**: New hotkey follows VLC syntax conventions

**Pass Threshold**: 75%

## Skills Tested

- Deep menu navigation (Tools → Preferences → Advanced)
- Settings search and location
- Hotkey binding interface
- Configuration persistence understanding
- Workflow optimization concepts

## Controls

- **Menu**: Tools → Preferences (Ctrl+P)
- **Advanced Mode**: Click "Show settings: All" at bottom-left
- **Navigate**: Interface → Hotkeys settings in sidebar
- **Modify**: Click hotkey field, press new key combination
- **Save**: Click "Save" button

## Real-World Context

A researcher analyzing video frames needs to capture screenshots frequently. The default Shift+S requires two hands and is awkward when controlling playback. Reconfiguring to F8 or another convenient key improves efficiency dramatically.

## Notes

VLC stores hotkey settings in `~/.config/vlc/vlcrc` with parameter names like `key-snapshot` (local) or `global-key-snapshot` (global). Valid hotkey format includes modifiers (Ctrl, Alt, Shift) and keys (letters, F-keys, etc.) separated by '+'.