# VLC Media Player Environment

A comprehensive VLC Media Player environment for `gym-anything`, designed for training agents on multimedia playback, manipulation, streaming, and management tasks.

## Overview

This environment provides a complete VLC Media Player setup with:
- **VLC Media Player 3.x+** with full codec support
- **Media analysis tools** (ffprobe, mediainfo) for verification
- **8 progressive tasks** from basic playback to video conversion
- **Generated sample media** (videos, audio, subtitles) for reproducibility
- **Verification utilities** for media analysis and output validation
- **VNC access** for visual observation and debugging
- **CLI and GUI support** for flexible automation

## Features

### Core Capabilities

1. **Media Playback**
   - Video and audio file playback
   - Seek, pause, play controls
   - Volume adjustment
   - Playback speed control
   - Loop and repeat modes

2. **Media Management**
   - Playlist creation and management
   - Media library organization
   - Subtitle loading and synchronization
   - Multiple audio track switching

3. **Media Manipulation**
   - Video effects (brightness, contrast, rotation, hue)
   - Audio effects (equalizer, spatial, stereo)
   - Filters and transformations
   - Snapshot capture at specific timestamps

4. **Media Conversion**
   - Transcode between formats
   - Audio/video codec conversion
   - Resolution and bitrate adjustment
   - Batch processing support

5. **Network Streaming**
   - HTTP, RTSP, RTP streaming
   - Network URL playback
   - Stream capture and recording

### Supported Formats

**Video**: MP4, AVI, MKV, MOV, FLV, WebM, MPEG, WMV, and many more
**Audio**: MP3, FLAC, AAC, OGG, WAV, WMA, and many more
**Subtitles**: SRT, ASS, SSA, SUB, VTT
**Playlists**: M3U, XSPF, PLS

## Directory Structure

```
vlc_env/
├── env.json                          # Environment specification
├── README.md                         # This file
├── scripts/
│   ├── install_vlc.sh               # VLC installation script
│   ├── setup_vlc.sh                 # VLC configuration script
│   └── task_utils.sh                # Shared task utilities
├── config/
│   └── vlcrc                        # VLC preferences
├── utils/
│   ├── __init__.py
│   └── vlc_verification_utils.py    # Verification utilities
├── assets/
│   └── .gitkeep                     # Sample media generated during setup
└── tasks/                            # Task definitions
    ├── README.md                     # Tasks overview
    ├── play_video/                   # Easy: Play video to completion
    ├── adjust_volume/                # Easy: Adjust volume level
    ├── seek_timestamp/               # Easy: Seek to timestamp
    ├── create_playlist/              # Medium: Create playlist
    ├── apply_effects/                # Medium: Apply video effects
    ├── load_subtitles/               # Medium: Load subtitles
    ├── take_snapshot/                # Medium: Capture snapshot
    └── convert_video/                # Medium+: Convert video format
```

## Usage

### Quick Start

```python
import gym_anything as ga

# Load the VLC environment
env = ga.from_config("vlc_env")

# Reset the environment
obs = env.reset(seed=42)

# Environment is ready with VLC installed
# Sample media available in /home/ga/Videos/
# VNC viewer accessible on port 5953
```

### Running Tasks

```bash
# Run a specific task
python -m gym_anything.cli run vlc_env --task play_video

# Validate task configuration
python -m gym_anything.cli validate vlc_env --task play_video

# Run all tasks sequentially
python -m gym_anything.cli run vlc_env --all-tasks
```

### Creating Custom Tasks

Tasks should be placed in the `tasks/` directory. Each task needs:

1. **`task.json`**: Task specification
2. **`setup_task.sh`**: Pre-task setup script
3. **`export_result.sh`**: Post-task export script
4. **`verifier.py`**: Verification logic
5. **`README.md`**: Task documentation

Example task structure:

```json
{
  "id": "my_vlc_task@1",
  "version": "1.0",
  "env_id": "vlc_env@0.1",
  "description": "Perform a specific VLC operation",
  "init": {
    "timeout_sec": 120,
    "max_steps": 30,
    "reward_type": "sparse"
  },
  "hooks": {
    "pre_task": "/workspace/tasks/my_vlc_task/setup_task.sh",
    "post_task": "/workspace/tasks/my_vlc_task/export_result.sh"
  },
  "success": {
    "spec": {
      "program": "verifier.py::verify_task"
    }
  }
}
```

## Task Overview

### 🟢 Easy Tasks

1. **Play Video** (`play_video`)
   - Play a video file to completion
   - Verify playback finished successfully
   - **Skills**: Basic playback, GUI interaction

2. **Adjust Volume** (`adjust_volume`)
   - Set volume to a target level (e.g., 75%)
   - Verify volume setting persisted
   - **Skills**: Volume controls, settings verification

3. **Seek Timestamp** (`seek_timestamp`)
   - Seek to a specific time in a video
   - Verify correct position reached
   - **Skills**: Timeline navigation, timestamp precision

### 🟡 Medium Tasks

4. **Create Playlist** (`create_playlist`)
   - Create playlist with multiple media files
   - Save playlist to file
   - **Skills**: Playlist management, file operations

5. **Apply Effects** (`apply_effects`)
   - Apply video effects (brightness, contrast)
   - Verify effects in output or config
   - **Skills**: Effects menu navigation, parameter adjustment

6. **Load Subtitles** (`load_subtitles`)
   - Load subtitle file and sync with video
   - Verify subtitles loaded correctly
   - **Skills**: Subtitle management, file association

7. **Take Snapshot** (`take_snapshot`)
   - Capture snapshot at specific timestamp
   - Verify snapshot image quality and timing
   - **Skills**: Snapshot feature, precise timing

### 🔴 Medium+ Tasks

8. **Convert Video** (`convert_video`)
   - Convert video from one format to another
   - Verify output format and quality
   - **Skills**: Conversion menu, format selection, quality settings

## User Accounts

The environment includes one pre-configured user account:

- **`ga`** (primary user)
  - Full sudo access
  - Home: `/home/ga`
  - VNC display: `:1`
  - Member of: audio, video, input groups
  - Sample media in: `/home/ga/Videos/`, `/home/ga/Music/`

## Network Ports

- **5953**: VNC server (external access)

## File Locations

### VLC Configuration
- Config directory: `/home/ga/.config/vlc/`
- Preferences: `/home/ga/.config/vlc/vlcrc`
- Playlists: `/home/ga/.local/share/vlc/`

### Sample Media
- Videos: `/home/ga/Videos/`
- Audio: `/home/ga/Music/`
- Subtitles: `/home/ga/Videos/subtitles/`

### Task Outputs
- Snapshots: `/home/ga/Pictures/vlc/`
- Converted media: `/home/ga/Videos/converted/`
- Playlists: `/home/ga/Videos/playlists/`
- Logs: `/tmp/vlc_*.log`

## Verification Utilities

The `utils/vlc_verification_utils.py` module provides helper functions:

```python
from vlc_verification_utils import *

# Analyze media files
video_info = get_video_info("/path/to/video.mp4")
audio_info = get_audio_info("/path/to/audio.mp3")

# Verify media properties
duration_ok = verify_video_duration(video_path, expected_duration, tolerance=1.0)
resolution_ok = verify_video_resolution(video_path, expected_width, expected_height)
codec_ok = verify_video_codec(video_path, expected_codec)

# Parse playlists
playlist_items = parse_m3u_playlist("/path/to/playlist.m3u")
xspf_items = parse_xspf_playlist("/path/to/playlist.xspf")

# Check VLC configuration
config = parse_vlc_config("/home/ga/.config/vlc/vlcrc")
volume = get_vlc_volume(config)

# Verify snapshot images
snapshot_ok = verify_snapshot_exists("/path/to/snapshot.png")
image_quality_ok = verify_image_quality("/path/to/snapshot.png", min_size_kb=50)
```

## GUI Automation

VLC can be controlled via GUI using `xdotool` and `wmctrl`:

```bash
# Launch VLC
vlc /path/to/video.mp4 &

# Focus VLC window
wmctrl -a "VLC media player"

# Play/Pause (Space)
xdotool key space

# Seek forward 10s (Shift+Right)
xdotool key shift+Right

# Volume up
xdotool key ctrl+Up

# Take snapshot
xdotool key shift+s

# Quit
xdotool key ctrl+q
```

## CLI (Headless) Mode

VLC can be controlled via CLI using `cvlc` (headless VLC):

```bash
# Play video (headless)
cvlc --play-and-exit /path/to/video.mp4

# Convert video
cvlc input.mp4 --sout='#transcode{vcodec=h264,acodec=mp3}:standard{access=file,mux=mp4,dst=output.mp4}' vlc://quit

# Extract snapshot
cvlc --video-filter=scene --scene-path=/output/dir --scene-prefix=snap --scene-format=png --start-time=10 --stop-time=11 --play-and-exit input.mp4

# Get media info
cvlc --no-video --no-audio --run-time=1 input.mp4 2>&1 | grep -i duration
```

## Logs

- **VLC GUI**: Check VLC messages (Tools → Messages) or `/tmp/vlc_messages.log`
- **VLC CLI**: Stderr output from `cvlc` commands
- **Setup**: `/tmp/vlc_setup.log`
- **Task logs**: `/tmp/vlc_task_*.log`

## Debugging

### Enable VNC Viewer
Connect to `localhost:5953` with password `password` to see the desktop.

### Check VLC Status
```bash
# Inside container
ps aux | grep vlc

# Check VLC version
vlc --version

# Test video playback (headless)
cvlc --play-and-exit /home/ga/Videos/sample.mp4
```

### Verify Sample Media
```bash
# List sample media
ls -lh /home/ga/Videos/
ls -lh /home/ga/Music/

# Check video info
ffprobe -v error -show_format -show_streams /home/ga/Videos/sample.mp4

# Check audio info
mediainfo /home/ga/Music/sample.mp3
```

### Test Media Analysis Tools
```bash
# Test ffprobe
ffprobe -version

# Test mediainfo
mediainfo --version

# Analyze video
ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height,duration -of default=noprint_wrappers=1 video.mp4
```

## Advanced Configuration

### Custom VLC Preferences

Modify `config/vlcrc` to set custom VLC preferences. Key settings:

```ini
# Disable tips and welcome dialog
[qt]
qt-privacy-ask=0
qt-start-minimized=0

# Video settings
[video]
video-on-top=0
snapshot-path=/home/ga/Pictures/vlc
snapshot-format=png

# Audio settings
[audio]
audio-volume=256  # 0-512, 256=100%

# Interface settings
[core]
loop=0
repeat=0
```

### Custom Sample Media

To add custom sample media:

1. Place media files in `assets/` directory
2. Modify `setup_vlc.sh` to copy them to user directories
3. Update task setup scripts to reference custom media

### Network Streaming

For network streaming tasks:

- Use public test streams (e.g., Big Buck Bunny streaming URLs)
- Set up local HTTP server with sample media
- Configure firewall rules in `env.json` if needed

## Troubleshooting

### VLC Won't Start
- Check `/tmp/vlc_*.log` for errors
- Ensure X11 display is running (`DISPLAY=:1`)
- Verify audio/video group membership

### Media Playback Issues
- Check codec support: `vlc --list | grep codec`
- Verify sample media generated: `ls -lh /home/ga/Videos/`
- Test with CLI: `cvlc --play-and-exit /home/ga/Videos/sample.mp4`

### Snapshot Not Saved
- Check snapshot directory: `/home/ga/Pictures/vlc/`
- Verify permissions: `ls -ld /home/ga/Pictures/vlc/`
- Check VLC preferences: `grep snapshot /home/ga/.config/vlc/vlcrc`

### Conversion Fails
- Check VLC conversion logs (stderr)
- Verify sufficient disk space
- Test with simpler conversion settings
- Ensure output directory exists and is writable

### VNC Connection Issues
- Ensure VNC server is running: `ps aux | grep x11vnc`
- Check port 5953 is accessible
- Verify password: `password`

## Contributing

To add new VLC tasks:

1. Create task directory in `tasks/`
2. Implement task.json, setup script, export script, verifier
3. Add README.md with task description
4. Update tasks/README.md with task overview
5. Test task validation: `python -m gym_anything.cli validate vlc_env --task <task_id>`

## License

VLC Media Player is licensed under GNU General Public License (GPL) v2+.
This environment configuration is part of the `gym-anything` project.

## References

- [VLC Official Website](https://www.videolan.org/vlc/)
- [VLC Command Line Help](https://wiki.videolan.org/VLC_command-line_help/)
- [VLC Streaming HowTo](https://wiki.videolan.org/Documentation:Streaming_HowTo/)
- [gym-anything Documentation](../../docs/)
