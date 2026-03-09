# Create Chapter Markers Task

**Difficulty**: 🟡 Medium  
**Skills**: Chapter metadata, video processing, command-line tools  
**Duration**: 180 seconds  
**Steps**: ~30

## Objective

Add chapter markers to a video file to enable easy navigation between sections. This is essential for educational content, long recordings, and organized media libraries.

## Task Description

Professor Chen has recorded a 45-minute lecture and needs to add chapter markers so students can navigate between topics. The agent must:

1. Work with source video: `/home/ga/Videos/lecture_recording.mp4`
2. Create chapter markers at:
   - **00:00** - "Introduction & Course Overview"
   - **15:30** - "Neural Network Fundamentals"  
   - **30:45** - "Practical Coding Examples"
3. Output video with chapters: `/home/ga/Videos/lecture_with_chapters.mp4`

## Expected Results

- Output video file created with embedded chapters
- 3 chapter markers at specified timestamps
- Video properties preserved (duration, resolution)
- Chapters accessible in VLC and other media players

## Verification Criteria

1. ✅ **Output Exists**: Video file with chapters created
2. ✅ **Video Preserved**: Duration and resolution match source (±2%)
3. ✅ **Chapters Present**: Exactly 3 chapters found in metadata
4. ✅ **Correct Timestamps**: Chapters at expected positions
5. ✅ **Chapter Titles**: Non-empty titles for each chapter

**Pass Threshold**: 70%

## Skills Tested

- Understanding video metadata structures
- Command-line tool usage (ffmpeg/MP4Box)
- File format knowledge
- Timestamp precision
- VLC chapter playback verification

## Implementation Approaches

### Method 1: FFmpeg (Recommended)

Create chapter metadata file: