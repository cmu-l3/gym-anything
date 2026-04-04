# Configure Shuffle No Repeat Task

**Difficulty**: 🟢 Easy-Medium  
**Skills**: Playlist management, playback mode configuration  
**Duration**: 60-90 seconds  
**Steps**: ~25

## Objective

Configure VLC Media Player to play all videos from a folder in shuffled (random) order, ensuring each video plays exactly once before any repeats, with continuous playback.

## Task Description

The agent must:
1. Add all videos from `~/Videos/ambient/` to VLC playlist
2. Enable shuffle/random playback mode
3. Configure repeat mode to "Repeat All" (NOT "Repeat One")
4. Ensure continuous playback (no stopping between files)

## Expected Results

- VLC playlist contains all 10 ambient videos
- Shuffle/random mode enabled (`random=1` in config)
- Repeat-all mode enabled (`loop=1` in config)
- Repeat-one mode NOT enabled (`repeat=0` in config)

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Shuffle Enabled**: Random playback mode active
3. ✅ **Correct Loop Mode**: Repeat-all enabled, repeat-one disabled

**Pass Threshold**: 70%

## Skills Tested

- Playlist management (adding folder contents)
- Playback mode configuration (shuffle vs sequential)
- Understanding VLC's repeat modes (repeat-one vs repeat-all)
- Settings persistence

## Controls

- **Playlist**: View → Playlist (Ctrl+L)
- **Add Folder**: Media → Open Folder
- **Shuffle**: Playback → Random (or shuffle button in controls)
- **Repeat**: Playback → Repeat All (click repeat button until loop icon shows)

## Notes

VLC has two distinct repeat modes:
- **Repeat One** (`repeat=1`): Plays same item forever
- **Repeat All** (`loop=1`): Loops entire playlist

For this task, shuffle should be combined with repeat-all, ensuring all videos play once before the shuffled order resets.