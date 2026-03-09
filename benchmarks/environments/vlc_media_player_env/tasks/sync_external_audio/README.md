# Sync External Audio Task

**Difficulty**: 🟡 Medium  
**Skills**: Multi-track audio management, external file loading, audio synchronization  
**Duration**: 120 seconds  
**Steps**: ~40

## Objective

Load an external audio file as an additional audio track in VLC and configure playback to use the external audio instead of the video's built-in audio.

## Task Description

The agent must:
1. VLC launches with a video containing poor-quality audio
2. Navigate to Audio → Audio Track → Load File menu
3. Select and load the external audio file (`/home/ga/Music/external_audio/replacement_audio.mp3`)
4. Switch to the external audio track for playback
5. Verify external audio is playing instead of original

## Expected Results

- External audio file loaded as additional track
- Audio track switched to external source (Track 2 or higher)
- Multiple audio tracks available in VLC
- External audio synchronized with video

## Verification Criteria

1. ✅ **Multiple Tracks**: VLC has 2+ audio tracks (original + external)
2. ✅ **External Track Active**: Non-embedded audio track is selected
3. ✅ **Task Completed**: Completion marker present

**Pass Threshold**: 70%

## Skills Tested

- Advanced menu navigation (Audio → Audio Track → Load File)
- File browser usage for audio files
- Multi-stream media understanding
- Audio track switching
- Professional post-production workflow

## Real-World Context

This task mirrors common content creation scenarios:
- Podcaster overlays video on separately recorded studio audio
- Educator adds clear narration to screen recording with poor mic audio
- Video journalist synchronizes external recorder audio with camera footage
- Content creator replaces poor audio with high-quality recording

## Controls

- **Menu**: Audio → Audio Track → Load File
- **Track Selection**: Audio → Audio Track → [Select Track]
- **Keyboard**: `B` to cycle through audio tracks