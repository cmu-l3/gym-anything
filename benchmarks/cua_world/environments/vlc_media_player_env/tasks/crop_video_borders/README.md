# Crop Video Borders Task

**Difficulty**: 🟡 Medium  
**Skills**: Video filters, geometric transformations, format conversion  
**Duration**: 180 seconds  
**Steps**: ~50

## Objective

Crop unwanted borders from all four sides of a video file using VLC's crop filter and save the result.

## Task Description

The agent must:
1. Open the source video with visible borders: `/home/ga/Videos/dashcam_raw.mp4`
2. Navigate to Effects and Filters menu
3. Apply crop filter with specific values:
   - Top: 60 pixels
   - Bottom: 80 pixels
   - Left: 20 pixels
   - Right: 20 pixels
4. Export/convert the video to `/home/ga/Videos/dashcam_cropped.mp4`

## Real-World Context

This simulates a common scenario: dashcam footage that includes unwanted dashboard (bottom), roof/mirror (top), and black bars (sides) that need to be removed before sharing the video.

## Expected Results

- Cropped video saved at `/home/ga/Videos/dashcam_cropped.mp4`
- Resolution: 1240x580 (from original 1280x720)
- Video codec: H.264
- Duration preserved (~15 seconds)

## Verification Criteria

1. ✅ **File Exists**: Cropped video file found
2. ✅ **Correct Resolution**: Width=1240, Height=580 (exactly)
3. ✅ **Valid Video**: Has H.264 codec and reasonable file size
4. ✅ **Duration Preserved**: Duration matches original (±1 second)

**Pass Threshold**: 75%

## Skills Tested

- Effects and Filters menu navigation
- Crop filter configuration
- Dimension calculation (understanding crop parameters)
- Video conversion workflow
- Output verification

## Controls

- **Menu**: Tools → Effects and Filters (Ctrl+E)
- **Video Effects → Geometry → Crop**: Set crop values
- **Media → Convert/Save (Ctrl+R)**: Export cropped video

## Notes

The original video has colored borders to make cropping visually obvious:
- Red border at top (60px to remove)
- Green border at bottom (80px to remove)
- Yellow borders on left and right (20px each to remove)