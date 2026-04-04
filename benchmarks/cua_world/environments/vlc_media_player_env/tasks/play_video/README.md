# Play Video Task

**Difficulty**: 🟢 Easy  
**Skills**: Basic playback, GUI interaction  
**Duration**: 60 seconds  
**Steps**: ~15

## Objective

Play a video file to completion using VLC Media Player. This is the most basic VLC task, testing fundamental playback functionality.

## Task Description

The agent must:
1. VLC launches automatically with a sample video
2. Allow the video to play to completion (30 seconds)
3. Video playback completes successfully

## Expected Results

- Video plays without errors
- Playback reaches the end of the video
- VLC logs show successful playback

## Verification Criteria

1. ✅ **Video File Valid**: Sample video file has correct properties
2. ✅ **Task Completion**: Completion marker file exists
3. ✅ **No Major Errors**: VLC logs show no critical errors

**Pass Threshold**: 65% (2/3 criteria)

## Skills Tested

- VLC interface recognition
- Understanding of media playback
- Basic agent observation of running applications

## Notes

This is a passive task - the agent mainly needs to observe the video playing. In more advanced scenarios, the agent might need to start playback, but here VLC auto-plays the video.
