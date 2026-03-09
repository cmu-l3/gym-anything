# Switch Audio Output Device Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio device configuration, application-level routing, settings persistence  
**Duration**: 90 seconds  
**Steps**: ~35

## Objective

Switch VLC's audio output device from the default speakers to reference headphones while audio is playing, without interrupting playback. This simulates a professional audio engineer's workflow of A/B testing mixes across different playback systems.

## Task Description

The agent must:
1. VLC launches with audio playing through default device (Studio_Monitors)
2. Navigate to VLC's audio output device settings
3. Switch output to "Reference_Headphones" sink
4. Verify audio routing changed without restarting VLC
5. Ensure the setting persists for future sessions

## Expected Results

- VLC audio stream routed to Reference_Headphones PulseAudio sink
- Playback continued without interruption during switch
- Audio device setting persisted in VLC configuration
- VLC wasn't restarted during the task

## Verification Criteria

1. ✅ **VLC Running**: VLC process is active
2. ✅ **Sink Exists**: Target audio sink (Reference_Headphones) is available
3. ✅ **Audio Routed Correctly**: VLC's audio stream connected to Reference_Headphones (PRIMARY - 50%)
4. ✅ **Config Persisted**: VLC configuration reflects the device change (25%)
5. ✅ **No Restart**: VLC uptime indicates continuous playback (15%)

**Pass Threshold**: 75% (must include audio routing check)

## Skills Tested

- Navigating nested preference dialogs during playback
- Understanding application vs. system audio routing
- PulseAudio device management concepts
- Applying changes that affect live playback
- Verifying configuration persistence

## Controls

- **Menu**: Audio → Audio Device → [Select device]
- **Preferences**: Tools → Preferences → Audio → Output device (requires "All" settings mode)
- **Hotkey**: Ctrl+P to open preferences

## Notes

The task involves PulseAudio concepts on Linux. Multiple virtual audio sinks are pre-configured to simulate different playback systems (studio monitors, headphones, desktop speakers). The agent must change VLC's output device while keeping the audio playing seamlessly.