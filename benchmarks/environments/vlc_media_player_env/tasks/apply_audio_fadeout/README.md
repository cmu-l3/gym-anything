# Apply Audio Fadeout Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio effects, media conversion, command-line tools  
**Duration**: 90 seconds  
**Steps**: ~40

## Objective

Apply an audio fade-out effect to a video file, making the audio gradually fade to silence over the last 15 seconds of the video.

## Task Description

The agent must:
1. Source video available at `/home/ga/Videos/bedtime_story.mp4` (60 seconds)
2. Apply audio fade-out starting at 45 seconds, duration 15 seconds
3. Save output to `/home/ga/Videos/bedtime_story_fadeout.mp4`
4. Preserve video quality

## Expected Results

- Output video file created at `/home/ga/Videos/bedtime_story_fadeout.mp4`
- Audio fades from full volume to silence over last 15 seconds
- Video portion preserved without quality loss
- File is playable and valid

## Verification Criteria

1. ✅ **File Exists**: Output video file found
2. ✅ **Audio Fadeout Present**: Volume decreases in fade region
3. ✅ **Fade Quality**: Final volume near silence (≥80% reduction)

**Pass Threshold**: 75%

## Skills Tested

- Audio filter understanding
- Media conversion/transcoding
- Command-line tool usage (ffmpeg)
- Or VLC conversion with audio filters
- File output verification

## Recommended Approach

### Option A: Using ffmpeg (recommended)