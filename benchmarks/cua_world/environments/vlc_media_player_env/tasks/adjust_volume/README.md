# Adjust Volume Task

**Difficulty**: 🟢 Easy  
**Skills**: Volume controls, settings verification  
**Duration**: 45 seconds  
**Steps**: ~20

## Objective

Adjust VLC Media Player's volume to a target level of 75% using either the GUI volume slider or keyboard shortcuts.

## Task Description

The agent must:
1. VLC launches with video at 100% volume
2. Locate and use volume controls
3. Adjust volume to approximately 75%
4. Volume setting persists in VLC configuration

## Expected Results

- Volume set to 75% (192 in VLC config, range 0-512)
- VLC config file reflects the change
- Volume control was actively used (changed from default 256)

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Volume at Target**: Volume within ±10% of target (75%)
3. ✅ **Volume Changed**: Volume different from initial 100%

**Pass Threshold**: 70%

## Skills Tested

- GUI element identification (volume slider)
- Keyboard shortcut usage (Ctrl+Up/Down)
- Precision control adjustment
- Settings persistence understanding

## Controls

- **GUI**: Click and drag volume slider
- **Keyboard**: 
  - `Ctrl+Up`: Increase volume
  - `Ctrl+Down`: Decrease volume
