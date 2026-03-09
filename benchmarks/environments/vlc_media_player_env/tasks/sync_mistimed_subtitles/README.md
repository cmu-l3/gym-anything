# Sync Mistimed Subtitles Task

**Difficulty**: 🟡 Medium  
**Skills**: Subtitle synchronization, timing adjustment, problem diagnosis  
**Duration**: 90 seconds  
**Steps**: ~40

## Objective

Fix mistimed subtitles that appear too early in a video by adjusting VLC's subtitle delay settings to synchronize them properly with the dialogue.

## Task Description

The agent must:
1. Open VLC with a video that has subtitles loaded
2. Diagnose that subtitles appear approximately 2.5 seconds too early
3. Adjust subtitle delay to compensate (+2.5 seconds)
4. Verify the subtitle synchronization setting persists in VLC configuration

## Real-World Context

This is one of the most common frustrations for viewers of foreign films and international content. When subtitles are downloaded from different sources or release versions, they often have timing offsets. Subtitles appearing too early spoil dialogue—viewers read what's about to be said before actors speak, ruining dramatic timing.

This issue affects millions of users who:
- Download fan-translated subtitles
- Watch content from international sources
- Use crowd-sourced subtitle databases (OpenSubtitles)
- Switch between theatrical and extended cuts

## Expected Results

- Subtitle delay setting configured to approximately +2.5 seconds
- Setting persists in VLC configuration file
- Positive delay applied (not negative)

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Delay Present**: Subtitle delay setting found in config
3. ✅ **Correct Range**: Delay value is +2.2s to +2.8s (±300ms tolerance)
4. ✅ **Positive Value**: Delay is positive (makes subtitles appear later)

**Pass Threshold**: 75%

## Skills Tested

- Problem diagnosis (understanding early vs late timing)
- Directional logic (positive delay for early subtitles)
- VLC subtitle controls (hotkeys H/G or menu)
- Precision adjustment (to ~100ms precision)
- Settings persistence understanding

## Controls

- **Keyboard Hotkeys**:
  - `H`: Increase subtitle delay (+50ms per press)
  - `G`: Decrease subtitle delay (-50ms per press)
  - `Shift+H` / `Shift+G`: Larger adjustments
  
- **Menu Method**:
  - Tools → Track Synchronization
  - Adjust "Subtitle track synchronization" value
  - Set to +2500ms (or +2.5 seconds)

- **Preferences Method**:
  - Tools → Preferences → Show All
  - Input/Codecs → Subtitle codecs → Subtitles
  - Set subtitle delay value

## Notes

- VLC stores subtitle delay in microseconds in config (2.5s = 2,500,000 μs)
- Positive delay makes subtitles appear LATER
- Negative delay makes subtitles appear EARLIER
- The test video has clear text markers to verify timing