# Configure Sleep Timer Task

**Difficulty**: 🟡 Medium  
**Skills**: Command-line VLC usage, runtime parameters, process automation  
**Duration**: 60 seconds  
**Steps**: ~25

## Objective

Configure VLC Media Player to play a long ambient video for exactly 45 minutes and then automatically quit. This simulates a realistic "sleep timer" use case where users want media to stop playing after falling asleep.

## Task Description

The agent must:
1. A 180-minute ambient video is available at `/home/ga/Videos/relaxing_thunderstorm.mp4`
2. Launch VLC with command-line parameters to play for exactly 45 minutes (2700 seconds)
3. Configure VLC to automatically quit (not just pause) after the duration

## Expected Results

- VLC launched with `--run-time=2700` or `--stop-time=2700` parameter
- VLC configured with `--play-and-exit` to quit after playback
- Correct video file specified in launch command
- Duration set to 45 minutes (2700 seconds) with reasonable tolerance

## Verification Criteria

1. ✅ **Video File Correct**: relaxing_thunderstorm.mp4 was used
2. ✅ **Runtime Configured**: --run-time or --stop-time parameter present
3. ✅ **Duration Correct**: Duration set to ~2700 seconds (40-50 minutes)
4. ✅ **Quit Configured**: --play-and-exit or vlc://quit present (optional)

**Pass Threshold**: 60%

## Skills Tested

- VLC command-line proficiency
- Understanding of runtime control flags
- Time unit conversion (minutes to seconds)
- Process control concepts
- Problem-solving (finding non-obvious feature)

## Controls

**Command-line examples:**