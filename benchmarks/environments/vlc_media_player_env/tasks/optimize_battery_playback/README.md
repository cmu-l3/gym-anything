# Optimize Battery Playback Task

**Difficulty**: 🟡 Medium  
**Skills**: VLC preferences configuration, hardware acceleration, power optimization  
**Duration**: 8 minutes  
**Steps**: ~50

## Objective

Configure VLC Media Player for battery-efficient video playback by enabling hardware acceleration and disabling CPU-intensive features to maximize laptop battery life during extended viewing sessions.

## Task Description

The agent must:
1. Open VLC Preferences (Tools → Preferences or Ctrl+P)
2. Switch to "All" settings mode to access advanced options
3. Enable hardware-accelerated decoding (Input/Codecs section)
4. Disable CPU-intensive post-processing features
5. Disable unnecessary video filters
6. Save configuration changes

## Scenario

**Context**: A remote consultant is on a 6-hour flight and needs to watch training videos on battery power. VLC's default settings are draining the battery too quickly. The goal is to configure VLC for minimum CPU usage while maintaining acceptable playback quality.

## Expected Results

- Hardware acceleration enabled (`avcodec-hw` ≠ "none")
- CPU-intensive filters and post-processing disabled
- Configuration changes persisted to vlcrc file
- Significant reduction in CPU usage during playback

## Verification Criteria

1. ✅ **Hardware Acceleration**: Enabled (not "none")
2. ✅ **H.264 Loop Filter**: Optimized (skip filter configured)
3. ✅ **Video Filters**: Disabled (no active filters)
4. ✅ **Deinterlacing**: Not actively consuming CPU

**Pass Threshold**: Hardware acceleration enabled + 50% of other optimizations

## Skills Tested

- VLC advanced preferences navigation
- Switching between Simple/All settings modes
- Understanding hardware vs software decoding
- Identifying CPU-intensive features
- Configuration file persistence
- Performance/quality tradeoffs

## Controls

- **Preferences**: Tools → Preferences (Ctrl+P)
- **Show All Settings**: Button in bottom-left of preferences window
- **Hardware Acceleration**: Input/Codecs → Hardware-accelerated decoding
- **Video Filters**: Video → Filters
- **Save**: Click "Save" button and restart VLC if prompted

## Notes

Hardware acceleration availability depends on system capabilities. On Linux, common options are VA-API, VDPAU, or "Automatic". Enabling hardware acceleration can reduce CPU usage by 40-60% during video playback.