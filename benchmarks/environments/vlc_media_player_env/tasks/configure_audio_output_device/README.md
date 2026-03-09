# Configure Audio Output Device Task

**Difficulty**: 🟡 Medium  
**Skills**: Advanced preferences navigation, audio configuration, settings persistence  
**Duration**: 90 seconds  
**Steps**: ~35

## Objective

Configure VLC Media Player to output audio to a specific non-default audio device (HDMI audio output) instead of the system default, addressing the common real-world scenario where users have multiple audio outputs and want per-application routing.

## Real-World Context

Users frequently connect laptops to TVs via HDMI or use multiple audio devices (built-in speakers, USB headphones, Bluetooth, HDMI). They often want VLC to output to a specific device (e.g., TV speakers via HDMI) while keeping system sounds on laptop speakers. This task tests the agent's ability to configure application-specific audio routing without changing system defaults.

## Task Description

The agent must:
1. VLC launches with a video playing
2. Navigate to advanced preferences (Show settings: All)
3. Access Audio → Output modules section
4. Configure audio output to use HDMI/non-default device
5. Save preferences to persist settings

## Expected Results

- VLC configuration modified to use specific audio output
- Audio output module explicitly set (not "auto")
- Device-specific settings point to HDMI or non-default device
- Settings persisted in VLC config file (`~/.config/vlc/vlcrc`)

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Audio Module Set**: Output module explicitly configured (not "auto")
3. ✅ **Device Specified**: Non-default device selected (ideally HDMI-related)

**Pass Threshold**: 70%

## Skills Tested

- Advanced preferences navigation (Show All Settings)
- Understanding audio output concepts (module vs device)
- Settings menu traversal (nested menus)
- Configuration persistence understanding
- Save/Apply button interaction

## Controls

- **Menu**: Tools → Preferences (Ctrl+P)
- **Advanced Mode**: Click "All" button at bottom-left of preferences
- **Navigation**: Audio → Output modules → ALSA/PulseAudio
- **Save**: Click "Save" button at bottom

## Notes

Audio output modules in VLC:
- **Default**: `aout=auto` (system default)
- **ALSA**: Direct hardware access, device selection via `alsa-audio-device=`
- **PulseAudio**: Audio server, device selection via `pulse-sink=`

Target configuration:
- Set `aout=alsa` or `aout=pulse` (not auto)
- Set device to HDMI-related value or specific non-default device