# Fix Aspect Ratio Task

**Difficulty**: 🟡 Medium  
**Skills**: Aspect ratio adjustment, video display settings  
**Duration**: 90 seconds  
**Steps**: ~30

## Objective

Fix the aspect ratio of a video file that's displaying incorrectly. The video contains 4:3 content but appears stretched in widescreen format.

## Real-World Scenario

You've digitized old family videos from VHS tapes (1990s era, recorded in 4:3 aspect ratio). When playing them in VLC, they appear stretched horizontally - everyone looks unnaturally wide. You need to fix the display aspect ratio to 4:3 so the video shows correct proportions with pillarboxing (black bars on sides).

## Task Description

The agent must:
1. Open the video file `/home/ga/Videos/old_family_video.mp4`
2. Navigate to aspect ratio settings
3. Change aspect ratio from default to **4:3**
4. Verify the setting persists in VLC configuration

## Expected Results

- Video displays with correct 4:3 aspect ratio
- VLC config shows `aspect-ratio=4:3`
- Video has pillarbox bars (black bars on left/right sides)

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file exists and is parseable
2. ✅ **Aspect Ratio Set**: Config shows aspect ratio set to 4:3
3. ✅ **VLC Used**: Evidence that VLC was used to open the video

**Pass Threshold**: 70%

## Skills Tested

- Video menu navigation
- Understanding of aspect ratios (4:3 vs 16:9)
- Display settings configuration
- Visual problem recognition

## Controls

- **Menu**: Video → Aspect Ratio → 4:3
- **Keyboard**: 'A' to cycle through aspect ratios