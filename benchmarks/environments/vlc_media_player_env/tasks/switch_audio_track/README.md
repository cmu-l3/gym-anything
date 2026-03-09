# Switch Audio Track Task

**Difficulty**: 🟡 Medium  
**Skills**: Audio track selection, multi-language media navigation  
**Duration**: 90 seconds  
**Steps**: ~40

## Objective

Switch from the default English audio track to the Japanese audio track in a multilingual video file using VLC's audio track selection menu.

## Task Description

The agent must:
1. VLC launches with a video containing two audio tracks (English default, Japanese)
2. Navigate to Audio → Audio Track menu
3. Switch from Track 1 (English) to Track 2 (Japanese)
4. Verify the audio track change persisted

## Expected Results

- Video is playing in VLC
- Japanese audio track (Track 2) is active
- Audio track selection persisted in VLC state/config

## Verification Criteria

1. ✅ **Video Playing**: Target video is loaded and playing
2. ✅ **Track Switched**: Japanese/Track 2 is now active
3. ✅ **Not Default**: Audio track changed from initial Track 1

**Pass Threshold**: 70%

## Skills Tested

- Nested menu navigation (Audio → Audio Track)
- Understanding multi-track media concepts
- Distinguishing between track numbers and labels
- State verification and persistence
- Audio track selection interface

## Real-World Context

This task simulates common scenarios where users:
- Language learners want to hear original audio for pronunciation practice
- Multilingual families need to switch between language preferences
- Film enthusiasts prefer original voice acting over dubs
- Users discover their media has multiple audio tracks but don't know how to switch

## Controls

- **Menu**: Audio → Audio Track → Track 2 (Japanese)
- **Keyboard**: `B` to cycle through audio tracks (may vary)
- **Right-click**: Context menu → Audio → Audio Track

## Notes

Many users don't realize videos can contain multiple audio tracks. This task tests the agent's ability to discover and utilize this feature. Track numbering may be 0-indexed or 1-indexed depending on VLC version, so verification handles both cases.