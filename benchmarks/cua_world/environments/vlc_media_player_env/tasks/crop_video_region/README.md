# Crop Video Region Task

**Difficulty**: 🟡 Medium  
**Skills**: Video filters, geometric transformations, conversion workflow  
**Duration**: 180 seconds  
**Steps**: ~50

## Objective

Remove hardcoded overlays (letterbox bars with burned-in subtitles) by applying a crop filter and converting the video to permanently remove unwanted regions.

## Task Description

The agent must:
1. Open a letterboxed video file with hardcoded text overlays
2. Apply VLC's crop filter to remove top and bottom portions
3. Configure conversion to apply the crop permanently
4. Save the cropped output to a specified location

## Expected Results

- Cropped video file created at `/home/ga/Videos/task_output/cropped_video.mp4`
- Output resolution changed from 1920x1080 to 1920x800
- Video duration preserved (~10 seconds)
- Main content preserved, letterbox bars removed

## Verification Criteria

1. ✅ **Output Exists**: Cropped video file found
2. ✅ **Resolution Correct**: Output is 1920x800 (±10 pixels)
3. ✅ **Duration Preserved**: Video duration ~10 seconds (±2 seconds)
4. ✅ **Valid Video**: File can be parsed and played

**Pass Threshold**: 75%

## Skills Tested

- Effects and Filters menu navigation
- Crop filter configuration
- Understanding geometric transformations
- Media conversion workflow
- Filter application during transcoding
- File output management

## Real-World Context

This task simulates cleaning up archived video content:
- Old TV recordings with channel logos or timestamps
- Videos with hardcoded subtitles you don't need
- Screen captures with visible UI elements
- Archive footage with added overlays from previous digitization

## Controls

- **Menu**: Tools → Effects and Filters (Ctrl+E)
- **Geometry Tab**: Video Effects → Geometry → Crop
- **Conversion**: Media → Convert/Save (Ctrl+R)
- **Profile Settings**: Ensure crop filter is included in conversion

## Notes

The input video has 140-pixel black bars on top and bottom with text overlay in the top bar. The goal is to crop these bars out, reducing resolution from 1920x1080 to 1920x800 while preserving the centered video content.

Crop can be applied temporarily for viewing, but the task requires permanent conversion with the crop filter applied.