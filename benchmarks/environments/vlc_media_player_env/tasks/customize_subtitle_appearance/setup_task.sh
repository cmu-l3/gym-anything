#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Customize Subtitle Appearance Task ==="

kill_vlc ga
sleep 1

TASK_DIR="/home/ga/Videos"
SUBTITLE_DIR="/home/ga/Videos"

# Ensure directories exist
mkdir -p "$TASK_DIR"
mkdir -p "$SUBTITLE_DIR"
chown -R ga:ga "$TASK_DIR"

# Generate a test video with bright, dark, and colored scenes to test subtitle readability
echo "Generating test video with varying brightness..."
if [ ! -f "$TASK_DIR/test_movie.mp4" ]; then
    # Create video with white (5s), black (5s), and yellow (5s) scenes
    su - ga -c "ffmpeg -y -f lavfi -i color=c=white:s=1280x720:d=5 -f lavfi -i color=c=black:s=1280x720:d=5 -f lavfi -i color=c=yellow:s=1280x720:d=5 -filter_complex '[0:v][1:v][2:v]concat=n=3:v=1:a=0[outv]' -map '[outv]' -pix_fmt yuv420p -t 15 '$TASK_DIR/test_movie.mp4' 2>/tmp/vlc_subtitle_setup.log" || {
        echo "Warning: ffmpeg test video generation failed, creating simple fallback"
        # Fallback: create a simple color video
        su - ga -c "ffmpeg -y -f lavfi -i color=c=white:s=1280x720:d=15 -pix_fmt yuv420p '$TASK_DIR/test_movie.mp4' 2>/tmp/vlc_subtitle_setup.log"
    }
fi

# Create SRT subtitle file with test content
cat > "$SUBTITLE_DIR/test_movie.srt" << 'EOF'
1
00:00:01,000 --> 00:00:04,000
This text should be visible on white background

2
00:00:06,000 --> 00:00:09,000
This text should be visible on black background

3
00:00:11,000 --> 00:00:14,000
This text should be visible on yellow background
EOF

chown ga:ga "$SUBTITLE_DIR/test_movie.srt"

# Reset VLC subtitle preferences to defaults (ensure clean state)
VLC_CONFIG="/home/ga/.config/vlc/vlcrc"
mkdir -p "$(dirname "$VLC_CONFIG")"
chown -R ga:ga "/home/ga/.config/vlc"

# Remove existing subtitle appearance settings to start fresh
if [ -f "$VLC_CONFIG" ]; then
    sed -i '/freetype-fontsize/d' "$VLC_CONFIG"
    sed -i '/freetype-rel-fontsize/d' "$VLC_CONFIG"
    sed -i '/freetype-background-opacity/d' "$VLC_CONFIG"
    sed -i '/freetype-background-color/d' "$VLC_CONFIG"
    sed -i '/freetype-outline-thickness/d' "$VLC_CONFIG"
    sed -i '/freetype-outline-color/d' "$VLC_CONFIG"
    echo "Subtitle settings reset to defaults"
fi

# Launch VLC without any video (agent will open it or open preferences directly)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_subtitle_appearance_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_subtitle_appearance_task.log || true
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

echo "=== Customize Subtitle Appearance Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Open Tools → Preferences (Ctrl+P)"
echo "  2. Click 'Show All Settings' at bottom left (to access advanced preferences)"
echo "  3. Navigate to: Video → Subtitles/OSD → Text renderer"
echo "  4. Configure the following:"
echo "     - Increase Font size to ≥30 (for large screen)"
echo "     - Enable Background: Set opacity to ≥128 (semi-transparent)"
echo "     - Set Background color to dark (black or dark gray)"
echo "  5. Click 'Save' button to persist changes"
echo "  6. You can test by opening: /home/ga/Videos/test_movie.mp4"
echo "     and loading subtitles: /home/ga/Videos/test_movie.srt"