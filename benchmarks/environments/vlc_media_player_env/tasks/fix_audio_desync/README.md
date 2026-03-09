# Fix Audio Desync Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio synchronization, troubleshooting, timing controls  
**Duration**: 60-90 seconds  
**Steps**: ~25

## Objective

Fix audio/video synchronization issues by adjusting VLC's audio delay setting to match a specified target timing offset.

## Real-World Context

Audio desynchronization is one of the most common and frustrating issues users encounter with video files. It occurs with:
- Poorly encoded video files from amateur sources
- Streaming rips with timing issues
- Container format conversions (e.g., MKV → MP4)
- Files that were improperly muxed/remuxed

The user needs to quickly fix this so the video is watchable.

## Task Description

The agent must:
1. Open a video file with noticeable audio desync
2. Access VLC's audio synchronization controls
3. Adjust the audio delay to the target value (e.g., +250ms)
4. Verify the adjustment was applied and persisted

## Expected Results

- Audio desync setting adjusted to target value (±50ms tolerance)
- Setting persists in VLC configuration
- Video audio and video tracks are now synchronized

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Desync Set Correctly**: Audio delay within ±50ms of target
3. ✅ **Setting Persisted**: Configuration saved properly

**Pass Threshold**: 70%

## Skills Tested

- Track Synchronization dialog navigation
- Understanding positive vs negative delays
- Numeric value adjustment
- Settings persistence verification
- Problem-solving for media issues

## Controls

- **Menu**: Tools → Track Synchronization
- **Keyboard Shortcuts**:
  - `J` - Delay audio (increase desync value)
  - `K` - Advance audio (decrease desync value)
- **Dialog**: Manual input of millisecond value

## Notes

- Positive values (+) delay the audio (audio plays later) - use when audio is AHEAD of video
- Negative values (-) advance the audio (audio plays earlier) - use when audio is BEHIND video
- VLC stores audio-desync values in milliseconds in the vlcrc config file