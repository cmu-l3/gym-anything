# Create Reaction GIF Task

**Difficulty**: 🟡 Medium  
**Skills**: Video conversion, segment extraction, format conversion, parameter optimization  
**Duration**: 120 seconds  
**Steps**: ~50

## Objective

Extract a specific segment from a video file and convert it to an optimized animated GIF suitable for social media sharing. This task simulates creating a reaction GIF for quick posting on social platforms.

## Task Description

The agent must:
1. VLC launches with a source video ready
2. Navigate to specific timestamp (12.5 seconds)
3. Extract a 3.5-second segment (12.5s to 16.0s)
4. Convert segment to animated GIF format
5. Optimize for file size (≤8 MB) and quality

## Expected Results

- Animated GIF created at `/home/ga/Videos/exports/reaction.gif`
- Duration: 3.5 seconds (±0.3s tolerance)
- File size: ≤8 MB
- Resolution: Max width 480px
- Frame rate: 10-15 fps (smooth but efficient)
- GIF is animated and loops

## Scenario Context

You're a community manager needing to quickly create a reaction GIF from a video clip. The GIF needs to be extracted and optimized for fast uploading on mobile networks while maintaining acceptable quality for social media.

## Verification Criteria

1. ✅ **File Exists & Valid**: GIF file exists and is valid format
2. ✅ **Duration Correct**: Duration is 3.5s (±0.3s)
3. ✅ **File Size**: File size ≤ 8 MB
4. ✅ **Resolution**: Width ≤ 500px
5. ✅ **Animated**: GIF has multiple frames (10+)

**Pass Threshold**: 75%

## Skills Tested

- Media conversion menu navigation
- Timestamp precision and seeking
- Format and codec selection
- Parameter optimization (quality vs size)
- Understanding of GIF limitations
- File output verification

## Approaches

### Method 1: VLC GUI Conversion (Recommended)
1. Media → Convert/Save (Ctrl+R)
2. Add source file
3. Click "Show more options"
4. Set start time: 12.5 seconds
5. Set stop time: 16.0 seconds
6. Choose Convert option
7. Create/select profile:
   - Encapsulation: GIF
   - Video codec: GIF
   - Frame rate: 12 fps
   - Scale: 0.5 or width=480
8. Set destination path
9. Start conversion

### Method 2: VLC Command Line