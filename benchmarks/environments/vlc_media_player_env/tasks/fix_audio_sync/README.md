# Fix Audio Sync Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio/video synchronization, track configuration, timing adjustment  
**Duration**: 90-120 seconds  
**Steps**: ~35

## Objective

Fix an audio-video synchronization problem in a lecture video by adjusting VLC's audio delay settings to compensate for audio that arrives too early (ahead of video).

## Real-World Scenario

A student has downloaded a recorded university lecture video to study for their upcoming exam. However, there's a noticeable audio synchronization problem—the professor's voice arrives approximately 300-400ms **before** their lips move on screen. This makes the video extremely distracting and difficult to follow.

The student needs to use VLC's audio delay feature to manually compensate for this timing mismatch so they can study effectively.

## Task Description

The agent must:
1. Open the video file with audio sync issues
2. Recognize the synchronization problem (audio leading video)
3. Navigate to Tools → Track Synchronization
4. Adjust the audio delay to compensate (~300-400ms positive delay)
5. Verify the setting is saved to VLC configuration

## Expected Results

- Audio delay adjusted in VLC configuration
- Delay value is positive (delaying audio to match video)
- Delay is within reasonable range (100ms to 800ms)
- Settings persisted to VLC config file

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Delay Configured**: Audio delay/desync setting present
3. ✅ **Correct Direction**: Delay is positive (audio delayed)
4. ✅ **Reasonable Value**: Delay in range [100, 800] milliseconds

**Pass Threshold**: 70%

## Skills Tested

- Problem diagnosis (recognizing sync issues)
- Menu navigation (Tools → Track Synchronization)
- Audio synchronization understanding
- Delay adjustment (positive vs negative)
- Settings persistence
- Real-world troubleshooting

## Controls

- **Menu**: Tools → Track Synchronization → Audio desync
- **Keyboard**: 
  - `j`: Delay audio (increase desync) - 50ms per press
  - `k`: Advance audio (decrease desync) - 50ms per press
  - These shortcuts adjust in real-time during playback

## Notes

- VLC audio desync is measured in milliseconds
- Positive values delay the audio relative to video
- Negative values advance the audio relative to video
- In this scenario, audio arrives ~350ms too early, so we need +300 to +400ms correction
- Settings are saved to `~/.config/vlc/vlcrc`