# Compress for Platform Limit Task

**Difficulty**: 🟡 Medium  
**Skills**: Video compression, transcoding, file size management  
**Duration**: 120 seconds  
**Steps**: ~50

## Objective

Compress a large video file to fit within a strict file size limit (10MB) for sharing via email or messaging platforms, while maintaining acceptable quality.

## Task Description

**Real-world scenario**: You've captured a 45-second video clip (35MB) that you want to email to family, but your email provider has a 10MB attachment limit. You need to compress the video so it fits while still being watchable.

The agent must:
1. Open VLC's conversion dialog (Media → Convert/Save)
2. Select the source video file
3. Configure compression settings (codec, bitrate, resolution)
4. Save compressed output under 10MB
5. Verify the video is still playable and maintains basic quality

## Expected Results

- Output file created at `/home/ga/Videos/compressed/birthday_email.mp4`
- File size is **strictly under 10MB** (10,485,760 bytes)
- Video duration preserved (~45 seconds ±2s)
- Format is MP4 (widely compatible)
- Quality is acceptable (minimum 480p width, reasonable bitrate)
- Video plays without errors

## Verification Criteria

1. ✅ **File Exists**: Compressed video file found
2. ✅ **Size Limit Met**: File is under 10MB (CRITICAL)
3. ✅ **Format Correct**: Output is MP4 format
4. ✅ **Duration Preserved**: Video is 43-47 seconds
5. ✅ **Quality Acceptable**: Resolution ≥480p width, valid codec
6. ✅ **Playable**: Video has valid properties and can be analyzed

**Pass Threshold**: 80%

## Skills Tested

- Media conversion menu navigation
- Understanding video compression concepts
- Bitrate and resolution trade-offs
- File size estimation
- Output format selection
- Quality vs. size balance

## Controls

- **Media → Convert/Save** (Ctrl+R): Open conversion dialog
- **Profile selection**: Choose or customize encoding profile
- **Settings adjustment**: Modify bitrate, resolution, codec
- **Destination**: Specify output file path

## Hints

**Using VLC GUI:**
1. Media → Convert/Save (Ctrl+R)
2. Add source file: `/home/ga/Videos/birthday_clip_source.mp4`
3. Click "Convert/Save" button
4. Choose profile (e.g., "Video - H.264 + MP3 (MP4)")
5. Edit profile (wrench icon):
   - Video codec: H.264
   - Video bitrate: ~1000-1500 kbps
   - Resolution: Consider 720p or 480p
   - Audio codec: MP3/AAC
   - Audio bitrate: 96-128 kbps
6. Set destination: `/home/ga/Videos/compressed/birthday_email.mp4`
7. Click Start

**Estimation**: 45 seconds at 1500 kbps video + 128 kbps audio ≈ 9MB

## Notes

This task simulates a common real-world frustration: sharing video clips via size-limited platforms (email, Discord, WhatsApp, Slack). VLC is one of the few free tools that can compress video without watermarks or cloud uploads.