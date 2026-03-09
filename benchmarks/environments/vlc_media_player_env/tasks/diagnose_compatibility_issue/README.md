# Diagnose Compatibility Issue Task

**Difficulty**: 🟡 Medium  
**Skills**: Codec information, diagnostic troubleshooting, technical literacy  
**Duration**: 120 seconds  
**Steps**: ~40

## Objective

Diagnose a video file's technical specifications to understand why it plays in VLC but fails on other platforms (YouTube, older devices). Extract codec, format, and quality details to identify compatibility issues.

## Scenario

You're preparing a promotional video for upload to YouTube. The video plays perfectly in VLC on your desktop, but YouTube rejects it with "Invalid file format" error. Your colleague also can't play it on their TV media player. You need to diagnose what's technically wrong with the file.

## Task Description

The agent must:
1. Open the problematic video in VLC (`/home/ga/Videos/problem_upload.mp4`)
2. Access VLC's codec information dialog (Tools → Codec Information or Media Information)
3. Extract technical specifications:
   - Video codec name
   - Video resolution (width × height)
   - Frame rate (FPS)
   - Video bitrate
   - Audio codec name
   - Audio sample rate
   - Audio channels
4. Document findings in a text report at `/home/ga/Documents/video_diagnostic_report.txt`

## Expected Results

- Diagnostic report file created
- Report contains video codec (HEVC/H.265)
- Report contains resolution (1920x1080)
- Report contains audio codec (AAC)
- Report contains sample rate (48000 Hz / 48 kHz)

## Verification Criteria

1. ✅ **Report Exists**: Report file created with reasonable content
2. ✅ **Video Codec Identified**: Report mentions HEVC/H.265
3. ✅ **Resolution Documented**: Report mentions 1920x1080
4. ✅ **Audio Codec Identified**: Report mentions AAC
5. ✅ **Sample Rate Documented**: Report mentions 48 kHz

**Pass Threshold**: 75% (3/4 technical details)

## Skills Tested

- Menu navigation (Tools → Codec Information)
- Reading and understanding technical specifications
- Text file creation and editing
- Diagnostic troubleshooting mindset
- Understanding video/audio formats

## Controls

- **Menu**: Tools → Codec Information (Ctrl+J) or Tools → Media Information (Ctrl+I)
- **Copy**: Ctrl+C to copy information
- **Text Editor**: Use any available text editor (gedit, nano, etc.)

## Real-World Application

This skill is essential for:
- Content creators troubleshooting upload failures
- Technical support diagnosing playback issues
- Meeting client/platform delivery specifications
- Understanding codec compatibility across devices

## Notes

The test video intentionally uses HEVC (H.265) codec, which has broad compatibility issues:
- Many older devices don't support it
- Some streaming platforms reject it
- Requires re-encoding to H.264 for broader compatibility