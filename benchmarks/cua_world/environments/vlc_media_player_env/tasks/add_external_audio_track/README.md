# Add External Audio Track Task

**Difficulty**: 🟡 Medium  
**Skills**: Multi-track audio, synchronization, track management  
**Duration**: 180 seconds  
**Steps**: ~40

## Objective

Load an external audio file as an additional audio track and synchronize it with the video by applying appropriate audio delay.

## Task Description

The agent must:
1. VLC launches with a video file (sample_movie.mp4)
2. Load an external audio commentary file (commentary.mp3) as an additional audio track
3. Apply audio delay of +3000ms to synchronize the tracks
4. Verify both audio sources can play together

## Real-World Scenario

A film enthusiast has a director's commentary track as a separate MP3 file. The commentary is meant to start 3 seconds after the movie begins. The agent must:
- Load the external audio file into VLC
- Set the correct audio delay (3 seconds)
- Ensure both the original movie audio and commentary play in sync

## Expected Results

- External audio track loaded into VLC
- Audio delay set to approximately +3000ms (±500ms tolerance)
- Configuration persisted in VLC settings

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Audio Delay Set**: Delay configured to ~3000ms
3. ✅ **External Track Loaded**: Evidence of commentary.mp3 being loaded

**Pass Threshold**: 70%

## Skills Tested

- Audio menu navigation
- Loading external files as tracks
- Track synchronization dialog usage
- Understanding of audio delay/sync concepts
- Multi-track audio management

## Controls

- **Audio → Audio Track → Load File**: Load external audio
- **Tools → Track Synchronization**: Adjust audio delay
- **Audio track synchronization slider**: Set delay in milliseconds

## Notes

- VLC supports multiple audio tracks but only one video track
- Audio delay is stored as `audio-desync` in vlcrc (microseconds)
- The commentary file has a different frequency tone (880 Hz vs 440 Hz) for testing
- When properly synced, both tones should play simultaneously