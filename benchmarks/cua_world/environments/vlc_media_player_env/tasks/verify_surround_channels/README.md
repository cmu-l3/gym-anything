# Verify Surround Channels Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio device configuration, preferences navigation, multi-channel audio understanding  
**Duration**: 120 seconds  
**Steps**: ~40

## Objective

Configure VLC Media Player to output audio to a multi-channel capable audio device and disable stereo downmixing to enable proper surround sound playback.

## Scenario

You've just set up a new 5.1 surround sound system and need to verify all channels are working. VLC is currently outputting to your laptop's built-in stereo speakers and downmixing multi-channel audio to stereo. You need to reconfigure VLC to use the surround sound receiver/soundcard and disable downmixing.

## Task Description

The agent must:
1. Open VLC's audio preferences (Tools → Preferences → Audio)
2. Change audio output device from "Built-in Audio" to a multi-channel capable device
3. Disable "Downmix to stereo" option to preserve multi-channel audio
4. Save preferences and apply changes

## Expected Results

- Audio output device changed to multi-channel capable device (USB/HDMI)
- Stereo downmixing disabled
- Preferences saved to VLC configuration file

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file exists and is parseable
2. ✅ **Multi-channel Device Selected**: Audio device set to USB/HDMI (not built-in)
3. ✅ **Downmixing Disabled**: Downmix setting is disabled (not =1)

**Pass Threshold**: 75%

## Skills Tested

- Preferences menu navigation (Tools → Preferences)
- Audio settings panel interaction
- Device dropdown selection
- Checkbox/option toggling
- Understanding of audio concepts (surround vs stereo, downmixing)
- Settings persistence

## Controls

- **Menu**: Tools → Preferences (or Ctrl+P)
- **Audio Tab**: Select "Audio" from sidebar
- **Device Dropdown**: Select audio output device
- **Checkboxes**: Disable "Downmix to stereo" or similar options
- **Save Button**: Save preferences before closing

## Notes

- VLC stores audio device settings in `~/.config/vlc/vlcrc`
- Audio device names may include: "HDMI", "USB", "DisplayPort", "Surround"
- Default device is often "Built-in Audio" or "Default"
- Some settings may require VLC restart to take effect