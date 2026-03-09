# Configure Seamless Loop Task

**Difficulty**: 🟡 Medium  
**Skills**: Configuration management, playlist creation, loop/repeat functionality  
**Duration**: 90-120 seconds  
**Steps**: ~35

## Objective

Configure VLC Media Player to create seamless, continuous looping playback of a video file suitable for use as a streaming background or presentation loop.

## Real-World Scenario

You're preparing for a live stream and need a "BRB" (Be Right Back) background video that loops seamlessly for hours. The video file has a fade-to-black ending that creates an awkward jump when it repeats. You need to configure VLC to loop the video continuously without visible transitions.

**User Persona**: Content creator, streamer, digital signage operator, presenter

**Pain Point**: Most videos aren't designed to loop perfectly. The default playback stops after the video ends, or the loop has jarring cuts that look unprofessional.

## Task Description

The agent must:
1. Open VLC with the background video available
2. Create a playlist file containing the video
3. Enable loop or repeat mode in VLC
4. Save configuration so it persists

## Expected Results

- Playlist file created at `/home/ga/Videos/playlists/stream_loop.m3u`
- Playlist contains `stream_background.mp4`
- Loop or repeat mode is enabled in VLC configuration
- Settings persist after closing VLC

## Verification Criteria

1. ✅ **Playlist Exists**: Playlist file found at expected location
2. ✅ **Playlist Contains Video**: Playlist includes stream_background.mp4
3. ✅ **Loop Enabled**: Loop or repeat mode is configured
4. ✅ **Configuration Persisted**: Settings saved to config files

**Pass Threshold**: 75%

## Skills Tested

- Playlist management
- File operations (save playlist)
- Loop/repeat mode configuration
- Understanding of VLC settings persistence
- Menu navigation (Playback → Loop/Repeat)

## Controls

- **Keyboard**: 
  - `L`: Toggle loop mode
  - `R`: Toggle repeat mode
  - `Ctrl+L`: Open playlist view
  - `Ctrl+S`: Save
- **Menu**: 
  - Media → Save Playlist to File
  - Playback → Loop (or Repeat)

## Notes

Loop mode replays the entire playlist continuously, while Repeat mode replays the current item continuously. Either approach works for this task. The key is that the configuration persists so the loop continues even after restarting VLC.