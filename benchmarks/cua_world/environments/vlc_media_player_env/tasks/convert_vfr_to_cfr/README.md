# Convert VFR to CFR Task

**Difficulty**: 🟡 Medium  
**Skills**: Video conversion, frame rate control, format compatibility  
**Duration**: 180 seconds  
**Steps**: ~50

## Objective

Convert a variable frame rate (VFR) screen recording to constant frame rate (CFR) at 30fps using VLC's conversion functionality to ensure compatibility with video editors and upload platforms.

## Task Description

The agent must:
1. Open VLC's conversion dialog
2. Select source VFR video file
3. Configure conversion settings for CFR output at 30fps
4. Start conversion process
5. Verify converted file maintains CFR, preserves quality, and has correct properties

## Expected Results

- Converted video file created at `/home/ga/Videos/screen_recording_cfr.mp4`
- Video has constant frame rate of 30fps (not variable)
- Resolution preserved at 1920x1080
- Duration approximately matches original (~120 seconds)
- H.264 codec with AAC audio

## Verification Criteria

1. ✅ **File Exists**: Converted video file found
2. ✅ **Resolution Preserved**: Output is 1920x1080
3. ✅ **Duration Matches**: Within 0.5s of original (audio sync maintained)
4. ✅ **Frame Rate Correct**: Exactly 30.000 fps (CFR)
5. ✅ **Codec Correct**: H.264 video codec
6. ✅ **File Valid**: Reasonable size and playable

**Pass Threshold**: 75% (5/6 criteria with weighted scoring)

## Skills Tested

- Media → Convert/Save menu navigation
- Understanding VFR vs CFR concepts
- Profile/format configuration
- Frame rate control settings
- Codec selection
- Transcoding progress monitoring
- Compatibility troubleshooting

## Real-World Context

This addresses a common problem where:
- OBS recordings create VFR files that cause audio drift in editors
- Mobile phone videos have variable frame rates
- Gaming capture software uses VFR for efficiency
- Upload platforms reject VFR videos
- Professional tools require CFR for predictable editing

## Controls

- **Media → Convert/Save (Ctrl+R)**: Open conversion dialog
- **Add**: Select source file
- **Profile dropdown**: Choose/customize output format
- **Settings (wrench icon)**: Configure codec and frame rate
- **Start**: Begin conversion

## Notes

- Conversion may take 30-60 seconds for the 2-minute video
- Key setting: Frame rate must be set to 30fps (not "keep original")
- VFR detection: Original video has mixed 30fps and 60fps segments
- Output must be true CFR (constant frame rate throughout)