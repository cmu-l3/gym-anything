# Fix Portrait Video Aspect Ratio Task

**Difficulty**: 🟡 Medium  
**Skills**: Video conversion, aspect ratio correction, geometric transformations  
**Duration**: 120 seconds  
**Steps**: ~45

## Objective

Convert a portrait-mode video (9:16 aspect ratio) to landscape format (16:9) using VLC's conversion and geometric transformation features, addressing the common "vertical video syndrome" problem.

## Task Description

The agent must:
1. Open VLC's conversion dialog (Media → Convert/Save)
2. Add the portrait video source file
3. Configure conversion with geometric transformation (crop or pad) to achieve 16:9 aspect ratio
4. Set output destination and start conversion
5. Wait for conversion to complete

## Expected Results

- Converted video file created at `/home/ga/Videos/corrected/portrait_corrected.mp4`
- Output video has 16:9 aspect ratio (width ≈ 1.778 × height)
- Video is in landscape orientation (width > height)
- Duration approximately preserved (~30 seconds ±10%)
- File is playable with valid codec

## Verification Criteria

1. ✅ **Output File Exists**: Converted video file present and non-empty
2. ✅ **Reasonable Size**: File size between 1MB and 100MB
3. ✅ **Correct Aspect Ratio**: Width/Height ratio between 1.73 and 1.83 (16:9 ±tolerance)
4. ✅ **Landscape Orientation**: Width > Height confirmed
5. ✅ **Duration Preserved**: Duration within 90-110% of original
6. ✅ **Video Playable**: Valid codec and parseable by ffprobe

**Pass Threshold**: 83% (requires 5 out of 6 criteria)

## Skills Tested

- Media conversion interface navigation
- Understanding of aspect ratios and video geometry
- Video filter/transformation configuration
- File path specification in save dialogs
- Progress monitoring for long-running operations
- Quality/format trade-off decisions

## Controls

- **Menu**: Media → Convert/Save (or Ctrl+R)
- **Profile**: Select conversion profile with video filters
- **Filters**: Video effects → Geometry → Crop/Canvas/Transform
- **Browse**: Select source file and destination path

## Real-World Context

A user recorded an important video on their smartphone in portrait mode and needs to include it in a landscape-oriented presentation. The video appears with large black bars on standard displays. They want to convert it to proper 16:9 landscape format by either cropping the top/bottom or adding padding to the sides.

## Conversion Approaches

**Option A - Crop (Fill Screen):**
- Extract center 16:9 portion of portrait video
- Pros: Fills screen, no black bars
- Cons: Loses top/bottom content

**Option B - Pad (Preserve All Content):**
- Add black bars to left/right sides
- Pros: Preserves all content
- Cons: Has letterboxing (pillarboxing)

**Option C - Smart Crop:**
- Center the subject and crop minimally
- Requires understanding of video content

Any approach that results in valid 16:9 landscape video is acceptable.

## Notes

- Conversion may take 30-60 seconds for a 30-second video
- VLC's convert dialog is complex with many options
- The source video is 1080x1920 pixels (portrait)
- Target output should be landscape (e.g., 1920x1080, 1280x720, etc.)
- Hardware acceleration is disabled to ensure compatibility