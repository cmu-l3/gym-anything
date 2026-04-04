# Correct Aspect Ratio Task

**Difficulty**: 🟡 Medium  
**Skills**: Video display configuration, aspect ratio understanding  
**Duration**: 180 seconds  
**Steps**: ~40

## Objective

Configure VLC Media Player to force the correct 4:3 aspect ratio for a video file that has incorrect aspect ratio metadata (flagged as 16:9), ensuring the video displays without vertical stretching.

## Task Description

The agent must:
1. Open the provided video file that appears vertically stretched
2. Recognize that people look unnaturally tall/thin (aspect ratio problem)
3. Navigate to VLC's aspect ratio settings
4. Force the correct 4:3 aspect ratio
5. Verify the video displays with correct proportions

## Real-World Context

**Scenario**: Old family videos were improperly ripped from DVDs. The video is actually 4:3 content (640x480) but was incorrectly encoded with 16:9 aspect ratio metadata, making everyone look stretched vertically.

This is extremely common with:
- Improperly ripped DVDs
- Old camcorder footage mishandled during digitization
- Content from different broadcast standards
- Amateur video editing with wrong export settings

## Expected Results

- VLC configuration contains aspect ratio override set to 4:3
- Setting persists in VLC config file
- Original video file unchanged (display override, not re-encoding)

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file exists and parseable
2. ✅ **Aspect Ratio Set**: Config contains 4:3 aspect ratio override
3. ✅ **Properly Formatted**: Setting is valid and will be applied

**Pass Threshold**: 70%

## Skills Tested

- Problem diagnosis (recognizing aspect ratio issues)
- VLC settings navigation
- Understanding display override vs. file modification
- Configuration persistence

## Controls

- **Menu**: Video → Aspect Ratio → 4:3
- **Menu**: Tools → Preferences → Video → Force aspect ratio
- **Right-click**: Video → Aspect Ratio → 4:3
- **Keyboard**: 'a' cycles through aspect ratios

## Notes

VLC stores aspect ratio settings in various config keys depending on version:
- `aspect-ratio=4:3`
- `vout-aspect-ratio=4:3`
- `custom-aspect-ratios=4:3`

The video is 640x480 (4:3) but flagged as 16:9, causing vertical stretch.