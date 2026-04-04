# Load Subtitles Task

**Difficulty**: 🟡 Medium  
**Skills**: Subtitle management, file association  
**Duration**: 60 seconds  
**Steps**: ~30

## Objective

Load a subtitle file (SRT format) and synchronize it with a playing video in VLC Media Player.

## Task Description

The agent must:
1. VLC launches with a video file
2. Navigate to subtitle menu
3. Load the subtitle file from `/home/ga/Videos/subtitles/sample.srt`
4. Verify subtitles are displayed

## Expected Results

- Subtitle file loaded into VLC
- Subtitles synchronized with video playback
- Subtitle settings persisted in VLC configuration

## Verification Criteria

1. ✅ **Config Accessible**: VLC config file parsed successfully
2. ✅ **Subtitle Loaded**: Subtitle file path found in VLC config
3. ✅ **Task Completed**: Completion marker present

**Pass Threshold**: 70%

## Skills Tested

- Subtitle menu navigation
- File browser usage
- Understanding subtitle file formats
- VLC configuration understanding

## Controls

- **Menu**: Subtitle → Add Subtitle File
- **Keyboard**: `V` to cycle through subtitle tracks
- **Right-click**: Context menu → Subtitle
