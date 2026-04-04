# Adjust Playback Speed Task

**Difficulty**: 🟡 Medium  
**Skills**: Playback controls, speed adjustment, temporal manipulation  
**Duration**: 90 seconds  
**Steps**: ~30

## Objective

Adjust VLC Media Player's playback speed to 1.5x (150% of normal speed) to enable faster media consumption - a critical feature for time-constrained users consuming educational content, podcasts, or video tutorials.

## Task Description

The agent must:
1. VLC launches with audio file at normal speed (1.0x)
2. Navigate to playback speed controls
3. Adjust playback speed to 1.5x using menu or keyboard shortcuts
4. Verify speed indicator displays 1.5x
5. Speed setting persists or is captured

## Expected Results

- Playback speed set to 1.5x (tolerance: ±0.05x)
- Speed indicator shows "1.5x" or "150%"
- Audio plays faster while maintaining pitch
- Speed setting different from initial 1.0x

## Verification Criteria

1. ✅ **Result Accessible**: Speed result file parsed successfully
2. ✅ **Speed at Target**: Playback speed is 1.5x (±0.05 tolerance)
3. ✅ **Speed Changed**: Speed modified from default 1.0x

**Pass Threshold**: 70%

## Skills Tested

- Playback menu navigation (Playback → Speed)
- Keyboard shortcut usage (`]` to increase, `[` to decrease)
- Speed indicator recognition
- Understanding temporal vs spatial controls
- Precision adjustment to target value

## Controls

- **Menu**: Playback → Speed → Faster/Slower/Normal
- **Keyboard**: 
  - `]`: Increase speed (typically +0.1x per press)
  - `[`: Decrease speed (typically -0.1x per press)
  - Press `]` approximately 5 times from 1.0x to reach 1.5x
- **Status Bar**: Shows current speed (e.g., "1.5x")

## Real-World Context

A commuter has a 40-minute podcast but only a 30-minute train ride. By setting playback to 1.5x, they can consume the full content within their time constraint while maintaining comprehension (research shows most people understand well up to 1.75x speed).

## Notes

- VLC maintains audio pitch at different speeds (time-stretching algorithm)
- Speed range: 0.25x to 4.0x (practical range for comprehension: 0.75x - 2.0x)
- Speed setting may persist across sessions depending on VLC configuration
- This tests temporal manipulation, distinct from seeking (spatial navigation)