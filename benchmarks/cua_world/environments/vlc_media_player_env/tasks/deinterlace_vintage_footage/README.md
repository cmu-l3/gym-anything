# Deinterlace Vintage Footage Task

**Difficulty**: 🟡 Medium  
**Skills**: Video filters, deinterlacing, format conversion, video restoration  
**Duration**: 180 seconds  
**Steps**: ~50

## Objective

Apply deinterlacing filter to vintage interlaced VHS footage and convert it to progressive format, eliminating visible combing artifacts.

## Task Description

The agent must:
1. Open VLC with access to interlaced source video
2. Recognize the video has interlacing artifacts (combing effect)
3. Enable deinterlacing filter (preferably Yadif mode)
4. Convert and save the video with deinterlacing applied
5. Output as progressive video format

## Expected Results

- Converted video file at `/home/ga/Videos/family_vhs_1995_deinterlaced.mp4`
- Output is progressive scan (not interlaced)
- Duration matches source (±5 seconds tolerance)
- Valid video codec (H.264, H.265, VP9, etc.)
- File size > 100 KB (valid video)

## Verification Criteria

1. ✅ **Output File Exists**: Deinterlaced video file created
2. ✅ **Duration Match**: Output duration approximately matches source
3. ✅ **Progressive Scan**: Output is progressive (field_order verified)
4. ✅ **Valid Codec**: Uses modern video codec

**Pass Threshold**: 75%

## Skills Tested

- Understanding interlaced vs progressive video
- Video filter navigation (Effects and Filters menu)
- Deinterlacing mode selection
- Video conversion with filters applied
- File format and codec understanding

## Controls

- **Menu**: Video → Deinterlace → [Mode]
- **Effects**: Tools → Effects and Filters → Video Effects → Deinterlace
- **Conversion**: Media → Convert/Save (Ctrl+R)
- **Recommended mode**: Yadif or Yadif (2x)

## Background

Interlaced video (common in VHS, broadcast TV, camcorders) stores each frame as two fields captured at different times. On modern progressive displays, this causes "combing" artifacts - horizontal lines visible during motion. Proper deinterlacing reconstructs full progressive frames for modern playback.

## Notes

This task simulates digitizing old family VHS tapes. The source video is generated with interlaced encoding to mimic real-world VHS captures. The goal is preservation of legacy media in a format suitable for modern displays.