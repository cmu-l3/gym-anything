# VLC Media Player Tasks Suite

## Overview

This comprehensive VLC tasks suite provides **8 carefully designed tasks** that progressively build from basic playback to advanced media manipulation, covering essential VLC workflows for multimedia agent training.

## Tasks Overview

| Task | Difficulty | Skills Tested | Primary Features | Duration |
|------|------------|---------------|------------------|----------|
| [**Play Video**](play_video/) | 🟢 Easy | Basic playback, GUI interaction | Play, Stop, Media controls | ~30s |
| [**Adjust Volume**](adjust_volume/) | 🟢 Easy | Volume controls, settings | Volume slider/hotkeys | ~20s |
| [**Seek Timestamp**](seek_timestamp/) | 🟢 Easy | Timeline navigation, precision | Seek bar, time display | ~20s |
| [**Create Playlist**](create_playlist/) | 🟡 Medium | Playlist management, file ops | Playlist window, Save | ~60s |
| [**Apply Effects**](apply_effects/) | 🟡 Medium | Video effects, adjustments | Effects menu, parameters | ~60s |
| [**Load Subtitles**](load_subtitles/) | 🟡 Medium | Subtitle management | Subtitle menu, file loading | ~45s |
| [**Take Snapshot**](take_snapshot/) | 🟡 Medium | Snapshot feature, timing | Snapshot hotkey, file output | ~30s |
| [**Convert Video**](convert_video/) | 🔴 Medium+ | Transcoding, format conversion | Convert/Save, codec selection | ~90s |

## Skill Progression

### 🟢 Easy Level
- Basic VLC interface interaction
- Simple playback controls
- Volume and seek operations

### 🟡 Medium Level
- Playlist creation and management
- Video effect application
- Subtitle handling
- Snapshot capture

### 🔴 Advanced Level
- Video transcoding and conversion
- Format selection and codec understanding
- Advanced media manipulation

## Verification Strategy

Each task employs appropriate verification methods:

- **File-based**: Check output files (snapshots, converted videos, playlists)
- **Media analysis**: Use ffprobe/mediainfo to verify properties
- **Config inspection**: Check VLC preferences and settings
- **Process monitoring**: Verify VLC state and logs

## Quick Start

```bash
# Run all tasks
python -m gym_anything.cli run vlc_env --all-tasks

# Run specific task
python -m gym_anything.cli run vlc_env --task play_video

# Validate tasks
python -m gym_anything.cli validate vlc_env
```

## Task Details

### 1. Play Video (Easy)
Play a sample video file to completion and verify successful playback.
- **Setup**: Launches VLC with sample video
- **Goal**: Let video play to end
- **Verification**: Check VLC logs for completion, verify video file properties

### 2. Adjust Volume (Easy)
Set VLC volume to a target level (e.g., 75%).
- **Setup**: Launches VLC
- **Goal**: Adjust volume using GUI or hotkeys
- **Verification**: Check VLC config file for volume setting

### 3. Seek Timestamp (Easy)
Seek to a specific timestamp in a video (e.g., 00:15).
- **Setup**: Launches VLC with video
- **Goal**: Navigate to exact timestamp
- **Verification**: Check VLC state or trigger action at timestamp

### 4. Create Playlist (Medium)
Create a playlist containing multiple media files and save it.
- **Setup**: Provides multiple sample videos/audio
- **Goal**: Create playlist, add items, save to file
- **Verification**: Parse playlist file, verify items present

### 5. Apply Effects (Medium)
Apply video effects (brightness, contrast) to playback.
- **Setup**: Launches VLC with video
- **Goal**: Navigate to effects menu, apply adjustments
- **Verification**: Check VLC config for effect settings

### 6. Load Subtitles (Medium)
Load a subtitle file and verify it's synchronized with video.
- **Setup**: Provides video and SRT subtitle file
- **Goal**: Load subtitle file in VLC
- **Verification**: Check VLC config for loaded subtitle path

### 7. Take Snapshot (Medium)
Capture a snapshot at a specific timestamp.
- **Setup**: Launches VLC with video
- **Goal**: Seek to timestamp, capture snapshot
- **Verification**: Check snapshot file exists with correct properties

### 8. Convert Video (Medium+)
Convert a video file from one format to another.
- **Setup**: Provides source video file
- **Goal**: Use VLC convert/save feature to transcode
- **Verification**: Analyze output file format, codec, and properties

## Common Verification Utilities

Located in `../utils/vlc_verification_utils.py`:

- `get_video_info()` - Extract video properties
- `get_audio_info()` - Extract audio properties
- `parse_m3u_playlist()` - Parse M3U playlists
- `parse_xspf_playlist()` - Parse XSPF playlists
- `verify_snapshot_exists()` - Verify snapshot file
- `verify_playlist_contents()` - Verify playlist items

## Sample Media

Generated during environment setup:

- `/home/ga/Videos/sample_video.mp4` - 30s test pattern with audio
- `/home/ga/Videos/color_test.mp4` - 10s colorful pattern
- `/home/ga/Videos/convert_source.mp4` - 5s video for conversion
- `/home/ga/Music/sample_audio.mp3` - 20s audio tone
- `/home/ga/Videos/subtitles/sample.srt` - Sample subtitle file

## Extending the Suite

To add new VLC tasks:

1. Create task directory in `tasks/`
2. Add `task.json`, setup/export scripts, verifier
3. Write comprehensive README.md
4. Update this overview
5. Test with `gym_anything.cli validate`

This task suite provides comprehensive coverage of VLC Media Player features for robust agent training!
