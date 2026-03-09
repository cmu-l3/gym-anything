# 🪞 Mirror Video Horizontal Task

**Difficulty**: 🟡 Medium  
**Skills**: Video transformation, effects menu navigation  
**Duration**: 90-120 seconds  
**Steps**: ~40

## Objective

Apply a horizontal flip/mirror transformation to a video using VLC's video effects filters. This creates a "mirror mode" where the video is flipped left-to-right, making it easier to follow along with tutorials where the instructor faces the camera.

## Task Description

The agent must:
1. Open a test video in VLC with directional indicators ("LEFT" and "RIGHT" text)
2. Navigate to VLC's Effects and Filters menu
3. Apply horizontal flip transformation
4. Verify the transformation is active and persisted

## Expected Results

- Transform filter enabled in VLC configuration
- Horizontal flip specifically applied (not rotation or vertical flip)
- Settings persisted in vlcrc file

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file exported and parsed
2. ✅ **Transform Filter Enabled**: Transform filter found in video-filter or vout-filter
3. ✅ **Horizontal Flip Applied**: Transform type is horizontal flip (hflip)

**Pass Threshold**: 70%

## Skills Tested

- Effects and Filters menu navigation (Tools → Effects and Filters)
- Video Effects panel interaction
- Understanding of video transformations vs rotations
- Settings persistence and configuration

## Controls

- **Menu**: Tools → Effects and Filters (Ctrl+E)
- **Tab**: Video Effects → Geometry
- **Checkbox**: Enable "Transform" 
- **Dropdown**: Select "Flip horizontally" or similar

## Real-World Context

Users need horizontal flipping when:
- Following makeup/beauty tutorials where instructor faces camera
- Learning hairstyling techniques
- Following physical therapy exercises
- Watching dance/workout videos where mirroring helps
- Sign language practice to match instructor's perspective

## Notes

This is different from rotation (90/180/270°). Horizontal flip creates a mirror image, swapping left and right sides while maintaining correct vertical orientation.