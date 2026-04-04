# Stress Test Playback Stability Task

**Difficulty**: 🟡 Medium  
**Skills**: Playback controls, stress testing, logging  
**Duration**: 60 seconds  
**Steps**: ~25

## Objective

Perform a pre-flight stability check on a video file by playing it at accelerated speed (3-4x) to verify it completes without crashes or errors. This simulates real-world scenarios where users need confidence that media will play reliably during important presentations or events.

## Task Description

The agent must:
1. VLC launches with a test video file
2. Increase playback speed to 3x-4x for accelerated testing
3. Allow video to play through substantially (at least 80% duration)
4. Verify VLC remains stable throughout playback
5. Document successful completion

## Expected Results

- Video plays at 3x-4x speed without crashes
- VLC remains stable for at least 80% of video duration
- Stability log captured showing no critical errors
- Result report confirms successful stress test

## Verification Criteria

1. ✅ **Stability Log Exists**: VLC log captured successfully
2. ✅ **No Crashes Detected**: Log contains no crash indicators
3. ✅ **Result Report Created**: Success confirmation documented

**Pass Threshold**: 70%

## Skills Tested

- Playback speed control (keyboard shortcuts)
- Understanding of stability testing concepts
- Log monitoring and documentation
- Timing and patience (waiting for completion)

## Real-World Context

**WHO**: Educators, presenters, event organizers, AV technicians  
**WHY**: Prevent embarrassing crashes during public playback  
**WHEN**: Night before presentations, after receiving suspicious files  
**SCENARIO**: "This video crashed VLC last time - I need to verify it works before my lecture tomorrow"

## Controls

- **Keyboard**: `]` (right bracket) - Increase playback speed
- **Keyboard**: `[` (left bracket) - Decrease playback speed  
- **Menu**: Playback → Speed → Faster

## Notes

At 4x speed, a 2-minute video takes only 30 seconds to play through. The agent should wait at least 24 seconds (80%) to verify stability. VLC's verbose logging captures any errors or warnings during playback.