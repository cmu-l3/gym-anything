# Batch Video Library Verification Task

**Difficulty**: 🟡 Medium  
**Skills**: Playlist management, batch operations, folder handling  
**Duration**: 90-120 seconds  
**Steps**: ~30

## Objective

Systematically verify multiple video files in an archive folder by creating a playlist, checking each file can play, and saving the verification playlist.

## Scenario

You are a digital archivist at a university library. After migrating video files to a new server, you need to verify that 5 important historical lecture recordings in `/home/ga/Videos/archive_check/` can still be opened and played in VLC. Create a systematic verification workflow.

## Task Description

The agent must:
1. Open VLC Media Player
2. Create a playlist from all video files in `/home/ga/Videos/archive_check/`
3. Systematically verify each video can play (open each briefly, ~5 seconds minimum)
4. Save the playlist containing all verified playable files to `/home/ga/Videos/playlists/verified_archive.m3u`

## Expected Results

- Playlist file created at `/home/ga/Videos/playlists/verified_archive.m3u`
- Playlist contains all 5 video files from archive_check folder:
  - lecture_01_intro.mp4
  - lecture_02_methodology.mp4
  - lecture_03_results.mp4
  - lecture_04_discussion.mp4
  - lecture_05_conclusion.mp4
- Playlist saved in M3U format

## Verification Criteria

1. ✅ **Playlist Exists**: Playlist file found and parseable
2. ✅ **Item Count**: Playlist has 5 items
3. ✅ **Expected Files**: Playlist contains all expected archive videos

**Pass Threshold**: 80%

## Skills Tested

- Playlist creation from folder
- Batch file handling
- Systematic verification workflow
- VLC playlist interface navigation
- File organization and saving
- Understanding of M3U playlist format

## Controls

- **Playlist View**: `Ctrl+L` or View → Playlist
- **Add Folder**: Media → Open Folder (Ctrl+F)
- **Save Playlist**: Media → Save Playlist to File (Ctrl+Y)
- **Navigation**: Arrow keys or click to select playlist items

## Tips

- Use "Open Folder" or "Add Folder" feature to quickly add all videos from archive_check
- The playlist panel (View → Playlist) helps manage multiple files
- You can quickly skip between videos in the playlist to verify each one plays
- Make sure to save as M3U format (not XSPF)
- Verify the save location is exactly `/home/ga/Videos/playlists/verified_archive.m3u`

## Real-World Context

This task simulates:
- Media library integrity checks after server migrations
- Batch video validation workflows
- Archival verification procedures
- Quality control for video collections
- Documentation of verified media assets