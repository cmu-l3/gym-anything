# Select Audio Track Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio track management, menu navigation  
**Duration**: 60 seconds  
**Steps**: ~25

## Objective

Open a video file with multiple audio tracks and select a specific audio track (English dub - Track 2) for playback using VLC's audio track selection menu.

## Scenario

Marcus, a film enthusiast, has downloaded a foreign film (Japanese anime movie) with multiple audio tracks. When he opens the file, it defaults to Japanese audio, but he wants to watch with the English dub since he's eating dinner and can't focus on reading subtitles. He needs to switch VLC to play the English dub audio track without stopping the video or losing his playback position.

## Task Description

The agent must:
1. Open the video file `/home/ga/Videos/test_multi_audio.mkv` with 3 audio tracks
2. Navigate to Audio → Audio Track menu
3. Select Track 2 (English dub)
4. Verify the correct track is selected and playing

## Expected Results

- VLC is playing the video with audio Track 2 selected
- Audio track selection persists during playback
- Selection can be verified via VLC's RC interface or configuration

## Verification Criteria

1. ✅ **VLC Running**: VLC is running with the test file
2. ✅ **Track Selected**: Audio track 2 is selected (or track index 1 if 0-indexed)
3. ✅ **Task Completed**: Completion marker present

**Pass Threshold**: 70%

## Skills Tested

- Audio track menu navigation (Audio → Audio Track)
- Understanding multi-track media files
- Track selection persistence
- Media player state management

## Controls

- **Menu**: Audio → Audio Track → Track 2
- **Keyboard**: `B` to cycle through audio tracks
- **Right-click**: Context menu → Audio → Audio Track

## Real-World Context

- **Foreign media consumption**: Choosing between original and dubbed audio
- **Accessibility**: Selecting audio description tracks for visually impaired
- **Language learning**: Switching between language tracks to compare
- **Content creation**: Verifying multiple audio mixes in video exports

## Notes

VLC's audio track numbering can vary:
- In the UI, tracks may be labeled "Track 1", "Track 2", "Track 3"
- Internally (RC/HTTP interface), tracks may be 0-indexed: 0, 1, 2
- The task accepts both Track 2 (UI) or Track 1 (0-indexed internal)