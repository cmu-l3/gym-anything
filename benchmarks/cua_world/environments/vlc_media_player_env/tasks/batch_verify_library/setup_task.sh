#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Batch Video Library Verification Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Setup directories
ARCHIVE_DIR="/home/ga/Videos/archive_check"
PLAYLIST_DIR="/home/ga/Videos/playlists"

echo "Creating archive and playlist directories..."
mkdir -p "$ARCHIVE_DIR"
mkdir -p "$PLAYLIST_DIR"

# Clean any existing files in archive directory
rm -f "$ARCHIVE_DIR"/*.mp4 2>/dev/null || true

# Clean any existing playlist files
rm -f "$PLAYLIST_DIR"/verified_archive.m3u 2>/dev/null || true

echo "Generating archive video files..."

# Video 1: Short lecture intro (10 seconds, 640x480)
echo "  Creating lecture_01_intro.mp4..."
ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=30 \
       -f lavfi -i sine=frequency=440:duration=10 \
       -pix_fmt yuv420p -c:v libx264 -preset ultrafast -c:a aac \
       "$ARCHIVE_DIR/lecture_01_intro.mp4" -y &>/dev/null

# Video 2: Medium lecture segment (15 seconds, 854x480)
echo "  Creating lecture_02_methodology.mp4..."
ffmpeg -f lavfi -i testsrc=duration=15:size=854x480:rate=30 \
       -f lavfi -i sine=frequency=523:duration=15 \
       -pix_fmt yuv420p -c:v libx264 -preset ultrafast -c:a aac \
       "$ARCHIVE_DIR/lecture_02_methodology.mp4" -y &>/dev/null

# Video 3: HD quality (12 seconds, 1280x720)
echo "  Creating lecture_03_results.mp4..."
ffmpeg -f lavfi -i testsrc=duration=12:size=1280x720:rate=30 \
       -f lavfi -i sine=frequency=330:duration=12 \
       -pix_fmt yuv420p -c:v libx264 -preset ultrafast -c:a aac \
       "$ARCHIVE_DIR/lecture_03_results.mp4" -y &>/dev/null

# Video 4: Shorter clip (8 seconds, 640x360)
echo "  Creating lecture_04_discussion.mp4..."
ffmpeg -f lavfi -i testsrc=duration=8:size=640x360:rate=30 \
       -f lavfi -i sine=frequency=392:duration=8 \
       -pix_fmt yuv420p -c:v libx264 -preset ultrafast -c:a aac \
       "$ARCHIVE_DIR/lecture_04_discussion.mp4" -y &>/dev/null

# Video 5: Full HD (13 seconds, 1920x1080)
echo "  Creating lecture_05_conclusion.mp4..."
ffmpeg -f lavfi -i testsrc=duration=13:size=1920x1080:rate=30 \
       -f lavfi -i sine=frequency=294:duration=13 \
       -pix_fmt yuv420p -c:v libx264 -preset ultrafast -c:a aac \
       "$ARCHIVE_DIR/lecture_05_conclusion.mp4" -y &>/dev/null

# Set ownership to ga user
chown -R ga:ga "$ARCHIVE_DIR"
chown -R ga:ga "$PLAYLIST_DIR"

echo "✅ Archive video files created:"
ls -lh "$ARCHIVE_DIR"

# Launch VLC (no file specified, user will add folder)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_batch_verify_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_batch_verify_task.log
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

# Focus VLC window
echo "Focusing VLC window..."
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Batch Video Library Verification Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "  1. Open the playlist view (Ctrl+L or View → Playlist)"
echo "  2. Add all videos from archive folder:"
echo "     Method A: Media → Open Folder (Ctrl+F)"
echo "              Navigate to: /home/ga/Videos/archive_check/"
echo "     Method B: Right-click in playlist → Add Folder"
echo "  3. Verify playlist shows all 5 lecture videos"
echo "  4. Optional: Click each video briefly to verify it plays"
echo "  5. Save playlist: Media → Save Playlist to File (Ctrl+Y)"
echo "  6. Save as: /home/ga/Videos/playlists/verified_archive.m3u"
echo "  7. Make sure format is M3U (not XSPF)"
echo ""
echo "📂 Archive directory: $ARCHIVE_DIR"
echo "💾 Target playlist: $PLAYLIST_DIR/verified_archive.m3u"