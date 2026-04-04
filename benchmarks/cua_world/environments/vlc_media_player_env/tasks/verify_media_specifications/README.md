# Verify Media Specifications Task

**Difficulty**: 🟢 Easy-Medium  
**Skills**: Media information access, technical specification reading, documentation  
**Duration**: 90 seconds  
**Steps**: ~35

## Objective

Access VLC's Media Information feature to verify technical specifications of a video file and document the findings.

## Task Description

**Scenario:** You're a content manager who received a video submission. Before accepting it, you must verify it meets technical requirements using VLC's Media Information feature.

The agent must:
1. Open the contributor's video in VLC (or it's already opened)
2. Access Media Information (Tools → Media Information or Ctrl+I)
3. Verify specifications:
   - Resolution: 1920x1080
   - Video Codec: H.264
   - Audio track present
4. Document findings in a verification file

## Expected Results

- Media Information window was accessed
- Verification document created at `/home/ga/Documents/video_specs_verified.txt`
- Document contains:
  - Resolution: 1920x1080 ✓
  - Video Codec: H.264 ✓
  - Audio: Present ✓
  - Status: APPROVED

## Verification Criteria

1. ✅ **Verification File Exists**: Documentation file created
2. ✅ **Resolution Documented**: Contains "1920x1080" or "1920×1080"
3. ✅ **Codec Documented**: Contains "H.264", "H264", or "AVC"
4. ✅ **Audio Documented**: Audio presence noted
5. ✅ **Approval Indicated**: Contains approval/acceptance status

**Pass Threshold**: 75%

## Skills Tested

- VLC Tools menu navigation
- Media Information dialog usage
- Reading technical specifications (codec, resolution)
- Technical documentation practices
- Understanding video metadata vs. visual content

## Controls

- **Keyboard**: `Ctrl+I` or `Ctrl+J` - Open Media Information
- **Menu**: Tools → Media Information (or Codec Information)
- **Tabs**: General, Codec Details, Metadata, Statistics

## Real-World Application

This task simulates common workflows in:
- Content management systems (verifying uploads)
- Video production QA processes
- Media archival and cataloging
- Troubleshooting playback issues
- Professional video delivery verification