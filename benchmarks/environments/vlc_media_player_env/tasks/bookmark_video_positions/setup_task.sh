#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Bookmark Video Positions Task ==="

kill_vlc ga
sleep 1

VIDEO_DIR="/home/ga/Videos"
BOOKMARK_DIR="/home/ga/Videos/bookmarks"
PLAYLIST_DIR="/home/ga/Videos/playlists"
DOCUMENTARY_VIDEO="$VIDEO_DIR/documentary.mp4"

# Create necessary directories
mkdir -p "$BOOKMARK_DIR" "$PLAYLIST_DIR"
chown -R ga:ga "$BOOKMARK_DIR" "$PLAYLIST_DIR"

# Check if documentary video already exists (to save time on repeated runs)
if [ -f "$DOCUMENTARY_VIDEO" ]; then
    echo "Documentary video already exists, skipping generation..."
    DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$DOCUMENTARY_VIDEO" 2>/dev/null || echo "0")
    
    # Verify duration is reasonable (at least 80 minutes = 4800 seconds)
    if (( $(echo "$DURATION < 4800" | bc -l 2>/dev/null || echo "1") )); then
        echo "Existing video too short, regenerating..."
        rm -f "$DOCUMENTARY_VIDEO"
    fi
fi

# Generate documentary video if needed (90 minutes)
if [ ! -f "$DOCUMENTARY_VIDEO" ]; then
    echo "Generating 90-minute documentary video (this may take 30-60 seconds)..."
    
    # Create a 90-minute video with changing colors to make timestamps distinguishable
    # Using testsrc with ultrafast preset for quick generation
    sudo -u ga ffmpeg -f lavfi -i "testsrc=duration=5400:size=1280x720:rate=5" \
        -f lavfi -i "sine=frequency=440:duration=5400" \
        -pix_fmt yuv420p -c:v libx264 -preset ultrafast -tune zerolatency \
        -c:a aac -b:a 64k \
        "$DOCUMENTARY_VIDEO" -y 2>/tmp/ffmpeg_documentary.log
    
    if [ ! -f "$DOCUMENTARY_VIDEO" ]; then
        echo "ERROR: Failed to generate documentary.mp4"
        cat /tmp/ffmpeg_documentary.log
        exit 1
    fi
    
    chown ga:ga "$DOCUMENTARY_VIDEO"
    echo "✓ Documentary video generated: $(du -h "$DOCUMENTARY_VIDEO" | cut -f1)"
fi

# Verify video duration
DURATION=$(ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "$DOCUMENTARY_VIDEO" 2>/dev/null || echo "0")

if (( $(echo "$DURATION < 4800" | bc -l 2>/dev/null || echo "1") )); then
    echo "ERROR: Video too short: ${DURATION}s (expected ~5400s)"
    exit 1
fi

echo "✓ Video duration: $(echo "$DURATION / 60" | bc)min $(echo "$DURATION % 60" | bc)s"

# Clear any existing VLC bookmarks/history to start fresh
sudo -u ga rm -f /home/ga/.local/share/vlc/ml.xspf 2>/dev/null || true
sudo -u ga rm -f /home/ga/.config/vlc/vlc-qt-interface.conf 2>/dev/null || true
sudo -u ga mkdir -p /home/ga/.local/share/vlc

# Create instructions file with exact timestamps
cat > /tmp/bookmark_instructions.txt << 'EOF'
╔════════════════════════════════════════════════════════════════╗
║          TASK: Create Bookmarks in Documentary Video          ║
╚════════════════════════════════════════════════════════════════╝

VIDEO: /home/ga/Videos/documentary.mp4 (90 minutes)

REQUIRED BOOKMARKS:
1. "Resume Point"    →  35:20  (00:35:20 / 2120 seconds)
2. "Mars Landing"    →  12:30  (00:12:30 / 750 seconds)
3. "Voyager Mission" →  58:00  (00:58:00 / 3480 seconds)
4. "Conclusion"      →  82:15  (01:22:15 / 4935 seconds)

═══════════════════════════════════════════════════════════════

METHOD 1 (Recommended): Create Playlist with Time Markers
  1. Open VLC
  2. Open Playlist View: Ctrl+L
  3. Add documentary.mp4 four times (one for each bookmark)
  4. For each playlist entry:
     - Right-click → Advanced Options → Start time
     - Enter timestamp in seconds: 2120, 750, 3480, 4935
  5. Save playlist: Media → Save Playlist to File
     → Save to: /home/ga/Videos/playlists/bookmarks.xspf

METHOD 2: Use VLC's Jump-to-Time Feature
  1. Open documentary.mp4 in VLC
  2. For each bookmark:
     a. Press Ctrl+T (Jump to Time)
     b. Enter timestamp (e.g., "35:20")
     c. Create a "bookmark" by adding to playlist or media library
  3. Add each position to playlist and save

METHOD 3: Create M3U Playlist Manually
  1. Create file: /home/ga/Videos/playlists/bookmarks.m3u
  2. Add entries with EXTVLCOPT markers:
     #EXTM3U
     #EXTINF:-1,Resume Point (35:20)
     #EXTVLCOPT:start-time=2120
     /home/ga/Videos/documentary.mp4
     #EXTINF:-1,Mars Landing (12:30)
     #EXTVLCOPT:start-time=750
     /home/ga/Videos/documentary.mp4
     ... (repeat for all bookmarks)

═══════════════════════════════════════════════════════════════

VERIFICATION: The task will check for:
  ✓ Playlist/media library files with bookmark data
  ✓ At least 4 time markers matching the required timestamps
  ✓ Files saved to disk (not just in-memory)

═══════════════════════════════════════════════════════════════
EOF

chown ga:ga /tmp/bookmark_instructions.txt

# Display instructions
cat /tmp/bookmark_instructions.txt

# Launch VLC with the documentary
echo ""
echo "Launching VLC with documentary..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --start-paused '$DOCUMENTARY_VIDEO' > /tmp/vlc_bookmark_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_bookmark_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo ""
echo "=== Bookmark Video Positions Task Setup Complete ==="
echo "📝 See /tmp/bookmark_instructions.txt for detailed instructions"
echo "🎬 VLC is ready with documentary.mp4 (90 minutes)"
echo "🎯 Create 4 bookmarks at: 12:30, 35:20, 58:00, 82:15"
echo ""