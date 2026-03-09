# Switch Video Angle Task

**Difficulty**: 🟡 Medium  
**Skills**: Multi-track navigation, video track switching  
**Duration**: 90 seconds  
**Steps**: ~35

## Objective

Switch between multiple video tracks (camera angles) in a multi-angle concert recording using VLC's video track menu.

## Task Description

The agent must:
1. VLC launches with a multi-track concert video file
2. Video contains 3 embedded video tracks (camera angles):
   - Track 0: Wide stage view (default)
   - Track 1: Close-up vocalist
   - Track 2: Drummer camera
3. Switch from default Track 0 to Track 1 (vocalist close-up)
4. Verify the track switch was successful

## Expected Results

- VLC detects all 3 video tracks in the file
- Agent successfully switches to video Track 1
- Track switch is verifiable through VLC state or configuration

## Verification Criteria

1. ✅ **Multi-track Video Valid**: Video file has multiple video tracks
2. ✅ **VLC Running**: VLC process is running with the concert video
3. ✅ **Track Switch Evidence**: Strong evidence that Track 1 is selected
4. ✅ **Visual Confirmation** (bonus): Screenshot shows Track 1 content

**Pass Threshold**: 60% (6/10 points)

## Skills Tested

- Understanding multi-stream media files
- Video Track menu navigation (Video → Video Track)
- Distinguishing between audio and video tracks
- Track identification and selection
- Alternative: Command-line track specification

## Controls

- **Menu**: Video → Video Track → Track 1
- **Keyboard**: `Shift+V` to cycle through video tracks
- **Alternative**: Launch with `--video-track-id=1` flag

## Real-World Context

Multi-angle video content is common in:
- Concert recordings (multiple camera perspectives)
- Sporting events (different camera angles)
- Educational content (instructor view vs. slides)
- DVD extras with alternate angles

Users often don't know how to access these alternative tracks, making this a valuable real-world skill.

## Notes

The video tracks are visually distinct (different colored backgrounds) to make verification easier. Track 0 is blue, Track 1 is red, Track 2 is green.