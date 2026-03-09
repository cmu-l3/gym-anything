# Generate Video Thumbnails Task

**Difficulty**: 🟡 Medium  
**Skills**: Scene filter usage, batch frame extraction, CLI automation, file management  
**Duration**: 90-120 seconds  
**Steps**: ~50

## Objective

Extract exactly 12 thumbnail images evenly distributed throughout a video file using VLC's scene filter. This simulates a real-world workflow where content creators or video editors need to quickly preview video content without playing the entire file.

## Real-World Scenario

You're a freelance video editor who just received raw footage from a client. Before investing hours in editing, you need to quickly assess what content exists in the 25-minute video. Rather than scrubbing through the timeline, you want to generate a visual "contact sheet" of thumbnails spanning the entire duration.

## Task Description

The agent must:
1. Analyze the video at `/home/ga/Videos/raw_footage.mp4`
2. Calculate the correct scene-ratio to extract exactly 12 frames
3. Use VLC's scene filter to extract thumbnails
4. Save thumbnails to `/home/ga/Pictures/thumbnails/`

## Expected Results

- Exactly 12 thumbnail images created
- Images saved to `/home/ga/Pictures/thumbnails/`
- Images are valid PNG/JPEG files
- Images represent different timestamps (not all identical)

## Verification Criteria

1. ✅ **Correct Count**: Exactly 12 thumbnail images exist
2. ✅ **Valid Images**: All images are valid and openable
3. ✅ **Content Diversity**: Images show different content (not all identical frames)

**Pass Threshold**: 75%

## Skills Tested

- Understanding VLC's scene filter
- Calculating frame extraction parameters (duration, fps, ratio)
- Working with media metadata (ffprobe)
- CLI automation of media processing
- File management and verification

## Hints

### Using VLC Scene Filter
