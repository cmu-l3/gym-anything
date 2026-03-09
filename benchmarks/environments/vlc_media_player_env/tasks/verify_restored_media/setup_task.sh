#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Verify Restored Media Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Clear VLC history to ensure clean verification
echo "Clearing VLC history..."
VLC_DATA_DIR="/home/ga/.local/share/vlc"
if [ -d "$VLC_DATA_DIR" ]; then
    # Remove media library and recent items
    rm -f "$VLC_DATA_DIR/ml.xspf" 2>/dev/null || true
    rm -f "$VLC_DATA_DIR/vlc-qt-interface.ini" 2>/dev/null || true
    echo "VLC history cleared"
fi

# Also clear recent files from config
VLC_CONFIG_DIR="/home/ga/.config/vlc"
if [ -f "$VLC_CONFIG_DIR/vlc-qt-interface.conf" ]; then
    # Remove recent items section
    sed -i '/\[RecentsMRL\]/,/^\[/d' "$VLC_CONFIG_DIR/vlc-qt-interface.conf" 2>/dev/null || true
fi

# Create restored backup directory
BACKUP_DIR="/home/ga/Videos/restored_backup"
echo "Creating restored backup directory: $BACKUP_DIR"
rm -rf "$BACKUP_DIR" 2>/dev/null || true
mkdir -p "$BACKUP_DIR"
chown ga:ga "$BACKUP_DIR"

# Copy/create sample media files to simulate restored backup
# Use existing sample files and create some additional ones
echo "Populating restored backup with media files..."

# Copy existing sample videos
if [ -f "/home/ga/Videos/sample_video.mp4" ]; then
    cp "/home/ga/Videos/sample_video.mp4" "$BACKUP_DIR/video_001.mp4"
fi

if [ -f "/home/ga/Videos/color_test.mp4" ]; then
    cp "/home/ga/Videos/color_test.mp4" "$BACKUP_DIR/video_002.mp4"
fi

# Copy existing sample audio
if [ -f "/home/ga/Music/sample_audio.mp3" ]; then
    cp "/home/ga/Music/sample_audio.mp3" "$BACKUP_DIR/audio_001.mp3"
fi

# Create additional small test video files using ffmpeg
# These simulate additional restored backup files
echo "Generating additional test media files..."

# Generate a simple 5-second test video (red screen)
su - ga -c "ffmpeg -f lavfi -i color=c=red:s=320x240:d=5 -f lavfi -i anullsrc=r=44100:cl=stereo -t 5 -vcodec libx264 -preset ultrafast -acodec aac -y '$BACKUP_DIR/video_003.mp4' > /tmp/ffmpeg_gen.log 2>&1" || {
    echo "Warning: Could not generate video_003.mp4"
}

# Generate another simple test video (blue screen)
su - ga -c "ffmpeg -f lavfi -i color=c=blue:s=320x240:d=5 -f lavfi -i anullsrc=r=44100:cl=stereo -t 5 -vcodec libx264 -preset ultrafast -acodec aac -y '$BACKUP_DIR/video_004.mp4' > /tmp/ffmpeg_gen2.log 2>&1" || {
    echo "Warning: Could not generate video_004.mp4"
}

# Generate a simple audio file (1kHz tone, 5 seconds)
su - ga -c "ffmpeg -f lavfi -i 'sine=frequency=1000:duration=5' -acodec libmp3lame -y '$BACKUP_DIR/audio_002.mp3' > /tmp/ffmpeg_audio.log 2>&1" || {
    echo "Warning: Could not generate audio_002.mp3"
}

# Set ownership
chown -R ga:ga "$BACKUP_DIR"

# Count files created
FILE_COUNT=$(find "$BACKUP_DIR" -type f \( -name "*.mp4" -o -name "*.mp3" -o -name "*.avi" -o -name "*.mkv" \) | wc -l)
echo "Created $FILE_COUNT media files in restored backup directory"

# List files for agent reference
echo "Media files to verify:"
ls -lh "$BACKUP_DIR"

# Save list of files to verify for later comparison
find "$BACKUP_DIR" -type f \( -name "*.mp4" -o -name "*.mp3" -o -name "*.avi" -o -name "*.mkv" -o -name "*.flv" -o -name "*.mov" \) > /tmp/backup_media_list.txt
echo "Expected file list saved to /tmp/backup_media_list.txt"

# Launch VLC (empty, agent must open files)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_verify_backup_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Verify Restored Media Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Navigate to: $BACKUP_DIR"
echo "  2. Systematically verify all media files by opening them in VLC"
echo "  3. Let each file play for at least 5-10 seconds to verify integrity"
echo "  4. Methods to verify files:"
echo "     - Media → Open File (Ctrl+O) and select files one by one"
echo "     - Media → Open Multiple Files to add all to playlist"
echo "     - Drag and drop files from file manager"
echo "     - Use playlist view (Ctrl+L) to manage files"
echo "  5. Ensure ALL $FILE_COUNT files are checked"