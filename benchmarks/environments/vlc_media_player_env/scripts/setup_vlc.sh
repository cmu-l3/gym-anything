#!/bin/bash
# set -euo pipefail

echo "=== Setting up VLC Media Player configuration ==="

# Set up VLC for a specific user
setup_user_vlc() {
    local username=$1
    local home_dir=$2
    
    echo "Setting up VLC for user: $username"

    # Give recursive full permissions to the user
    sudo chmod -R 777 /home/$username/.cache
    
    # Create VLC config directory
    sudo -u $username mkdir -p "$home_dir/.config/vlc"
    sudo -u $username mkdir -p "$home_dir/.local/share/vlc"
    sudo -u $username mkdir -p "$home_dir/.cache/vlc"
    
    # Create media directories
    sudo -u $username mkdir -p "$home_dir/Videos"
    sudo -u $username mkdir -p "$home_dir/Videos/converted"
    sudo -u $username mkdir -p "$home_dir/Videos/playlists"
    sudo -u $username mkdir -p "$home_dir/Videos/subtitles"
    sudo -u $username mkdir -p "$home_dir/Music"
    sudo -u $username mkdir -p "$home_dir/Pictures/vlc"
    sudo -u $username mkdir -p "$home_dir/Desktop"
    
    # Copy custom VLC preferences if available
    if [ -f "/workspace/config/vlcrc" ]; then
        sudo -u $username cp "/workspace/config/vlcrc" "$home_dir/.config/vlc/"
        chown $username:$username "$home_dir/.config/vlc/vlcrc"
        echo "  - Copied custom vlcrc"
    else
        # Create default vlcrc with optimizations
        cat > "$home_dir/.config/vlc/vlcrc" << 'VLCRCEOF'
[qt]
qt-privacy-ask=0
qt-updates-notif=0
qt-start-minimized=0
qt-continue=0

[core]
avcodec-hw=none
avcodec-hw=0
vout=x11
metadata-network-access=0
loop=0
repeat=0
video-title-show=0
video-title-timeout=1000

[video]
video-on-top=0
snapshot-path=/home/ga/Pictures/vlc
snapshot-format=png
snapshot-prefix=vlc-snap

[audio]
audio-volume=256

[hotkeys]
key-play-pause=Space
key-next=n
key-prev=p
key-vol-up=Ctrl+Up
key-vol-down=Ctrl+Down
key-snapshot=Shift+s
key-quit=Ctrl+q
VLCRCEOF
        # Replace /home/ga with actual home dir
        sed -i "s|/home/ga|$home_dir|g" "$home_dir/.config/vlc/vlcrc"
        chown $username:$username "$home_dir/.config/vlc/vlcrc"
        echo "  - Created default vlcrc"
    fi
    
    # Generate sample video files
    echo "  - Generating sample video files..."
    
    # Sample video 1: 30 second test pattern with audio (for playback tasks)
    sudo -u $username ffmpeg -f lavfi -i testsrc=duration=30:size=1280x720:rate=30 \
        -f lavfi -i sine=frequency=440:duration=30 \
        -pix_fmt yuv420p -c:v libx264 -preset ultrafast -crf 23 \
        -c:a aac -b:a 128k \
        "$home_dir/Videos/sample_video.mp4" \
        -y -loglevel error 2>/dev/null || echo "Warning: Could not generate sample_video.mp4"
    
    # Sample video 2: 10 second colorful pattern (for snapshot/effects tasks)
    sudo -u $username ffmpeg -f lavfi -i testsrc=duration=10:size=1280x720:rate=30 \
        -vf "hue=s=0:H=t*360/10" \
        -pix_fmt yuv420p -c:v libx264 -preset ultrafast -crf 23 \
        "$home_dir/Videos/color_test.mp4" \
        -y -loglevel error 2>/dev/null || echo "Warning: Could not generate color_test.mp4"
    
    # Sample video 3: Short clip for conversion (5 seconds)
    sudo -u $username ffmpeg -f lavfi -i testsrc=duration=5:size=640x480:rate=15 \
        -f lavfi -i sine=frequency=1000:duration=5 \
        -pix_fmt yuv420p -c:v libx264 -preset ultrafast -crf 28 \
        -c:a aac -b:a 96k \
        "$home_dir/Videos/convert_source.mp4" \
        -y -loglevel error 2>/dev/null || echo "Warning: Could not generate convert_source.mp4"
    
    # Generate sample audio files
    echo "  - Generating sample audio files..."
    
    # Sample audio 1: 20 second tone
    sudo -u $username ffmpeg -f lavfi -i sine=frequency=440:duration=20 \
        -c:a libmp3lame -b:a 192k \
        "$home_dir/Music/sample_audio.mp3" \
        -y -loglevel error 2>/dev/null || echo "Warning: Could not generate sample_audio.mp3"
    
    # Sample audio 2: 15 second different tone
    sudo -u $username ffmpeg -f lavfi -i sine=frequency=880:duration=15 \
        -c:a aac -b:a 128k \
        "$home_dir/Music/sample_audio2.m4a" \
        -y -loglevel error 2>/dev/null || echo "Warning: Could not generate sample_audio2.m4a"
    
    # Generate sample subtitle file
    echo "  - Generating sample subtitle file..."
    cat > "$home_dir/Videos/subtitles/sample.srt" << 'SRTEOF'
1
00:00:00,000 --> 00:00:05,000
This is the first subtitle line

2
00:00:05,000 --> 00:00:10,000
This is the second subtitle line

3
00:00:10,000 --> 00:00:15,000
And this is the third

4
00:00:15,000 --> 00:00:20,000
Fourth subtitle appears here

5
00:00:20,000 --> 00:00:25,000
Fifth and final subtitle
SRTEOF
    chown $username:$username "$home_dir/Videos/subtitles/sample.srt"
    echo "  - Created sample subtitle file"
    
    # Set proper permissions for all media files
    chown -R $username:$username "$home_dir/Videos"
    chown -R $username:$username "$home_dir/Music"
    chown -R $username:$username "$home_dir/Pictures/vlc"
    
    # Create desktop shortcut
    cat > "$home_dir/Desktop/VLC.desktop" << DESKTOPEOF
[Desktop Entry]
Name=VLC Media Player
Comment=Play multimedia files
Exec=vlc %U
Icon=vlc
StartupNotify=true
Terminal=false
MimeType=video/*;audio/*;
Categories=AudioVideo;Player;
Type=Application
DESKTOPEOF
    chown $username:$username "$home_dir/Desktop/VLC.desktop"
    chmod +x "$home_dir/Desktop/VLC.desktop"
    echo "  - Created desktop shortcut"
    
    # Create launch script
    cat > "$home_dir/launch_vlc.sh" << 'LAUNCHEOF'
#!/bin/bash
# Launch VLC with optimized settings
export DISPLAY=${DISPLAY:-:1}

# Ensure proper permissions for X11
xhost +local: 2>/dev/null || true

# Launch VLC
vlc "$@" > /tmp/vlc_$USER.log 2>&1 &

echo "VLC started"
echo "Log file: /tmp/vlc_$USER.log"
LAUNCHEOF
    chown $username:$username "$home_dir/launch_vlc.sh"
    chmod +x "$home_dir/launch_vlc.sh"
    echo "  - Created launch script"
}

# Setup for ga user (the main VNC user)
if id "ga" &>/dev/null; then
    setup_user_vlc "ga" "/home/ga"
fi

# Create utility scripts
cat > /usr/local/bin/vlc-info << 'INFOEOF'
#!/bin/bash
# VLC media info utility
# Usage: vlc-info <media_file>

if [ $# -eq 0 ]; then
    echo "Usage: vlc-info <media_file>"
    exit 1
fi

echo "=== Media Information ==="
echo "File: $1"
echo ""
echo "--- MediaInfo ---"
mediainfo "$1" 2>/dev/null || echo "mediainfo failed"
echo ""
echo "--- FFprobe ---"
ffprobe -v error -show_format -show_streams "$1" 2>/dev/null || echo "ffprobe failed"
INFOEOF
chmod +x /usr/local/bin/vlc-info

echo "=== VLC Media Player configuration completed ==="

# Do not auto-launch VLC here - let task scripts handle launching
echo "VLC is ready! Users can:"
echo "  - Launch from desktop shortcut"
echo "  - Run 'vlc' from terminal"
echo "  - Run '~/launch_vlc.sh <file>' for optimized launch"
echo "  - Use 'cvlc' for headless operations"
echo "  - Use 'vlc-info <file>' to inspect media files"
