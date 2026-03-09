# Disable Video Track Task

**Difficulty**: 🟡 Medium  
**Skills**: Advanced preferences navigation, resource optimization  
**Duration**: 120 seconds  
**Steps**: ~35

## Objective

Configure VLC to disable video rendering while maintaining audio playback - a critical technique for conserving battery life and reducing CPU usage.

## Task Description

**Real-World Scenario**: You're on a long flight with limited battery. You need to listen to a lecture video but watching it will drain your battery too quickly. Configure VLC to play only audio, skipping video decoding entirely.

The agent must:
1. Open VLC Preferences (Tools → Preferences)
2. Switch to "All" settings mode
3. Navigate to Video settings
4. Disable video output or rendering
5. Save preferences and verify configuration

## Expected Results

- VLC preferences configured with video disabled
- Settings persist in vlcrc configuration file
- Audio playback still functional

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Video Disabled**: Video output set to disabled/dummy/none
3. ✅ **Config Valid**: Settings properly formatted

**Pass Threshold**: 75%

## Skills Tested

- Advanced preferences navigation (Simple vs. All views)
- Settings tree navigation
- Configuration persistence understanding
- Resource optimization awareness

## Controls

- **Ctrl+P**: Open preferences
- **Menu**: Tools → Preferences → Show settings: All
- **Navigate**: Video section in left tree
- **Setting**: Disable video output or set to "Disable"/"Dummy"

## Notes

This task tests understanding of VLC's advanced configuration system. The video output can be disabled in multiple ways:
- Setting vout module to "dummy" or "none"
- Disabling video checkbox
- Setting no-video flag