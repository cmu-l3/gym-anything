# Create Playlist Task

**Difficulty**: 🟡 Medium  
**Skills**: Playlist management, file operations  
**Duration**: 90 seconds  
**Steps**: ~40

## Objective

Create a playlist containing multiple media files and save it to a file using VLC's playlist functionality.

## Task Description

The agent must:
1. Open VLC's playlist view
2. Add multiple media files to the playlist
3. Save the playlist to disk as M3U format

## Expected Results

- Playlist file created at `/home/ga/Videos/playlists/my_playlist.m3u`
- Playlist contains at least 3 items:
  - sample_video.mp4
  - color_test.mp4
  - sample_audio.mp3

## Verification Criteria

1. ✅ **Playlist Exists**: Playlist file found and parseable
2. ✅ **Item Count**: Playlist has 3+ items
3. ✅ **Expected Files**: Playlist contains expected media files

**Pass Threshold**: 75%

## Skills Tested

- Playlist window navigation
- File browser usage
- Multiple file selection
- Save dialog interaction
- Understanding of playlist concepts

## Controls

- `Ctrl+L`: Open playlist view
- **Media → Save Playlist to File**: Save playlist
- **Playlist → Add File**: Add media files
