#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Deinterlace Vintage Footage Task ==="

kill_vlc ga
sleep 1

# Ensure video directory exists
VIDEO_DIR="/home/ga/Videos"
mkdir -p "$VIDEO_DIR"
chown ga:ga "$VIDEO_DIR"

SOURCE_FILE="$VIDEO_DIR/family_vhs_1995.avi"

# Generate interlaced test video simulating VHS digitization
echo "Generating interlaced sample video (simulating VHS footage)..."

# Create video with interlaced encoding and motion to show combing artifacts
# Using testsrc with scrolling pattern and interlaced flags
su - ga -c "ffmpeg -f lavfi -i testsrc=duration=45:size=720x480:rate=30000/1001 \
  -f lavfi -i 'sine=frequency=440:duration=45' \
  -vf \"drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='Family Vacation 1995':fontsize=48:fontcolor=white:x=(w-text_w)/2:y=h-th-30:box=1:boxcolor=black@0.7:boxborderw=5, \
       drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='Digitized from VHS Tape':fontsize=24:fontcolor=yellow:x=(w-text_w)/2:y=30:box=1:boxcolor=black@0.5\" \
  -flags +ilme+ildct \
  -c:v mpeg4 -q:v 5 \
  -c:a mp3 -b:a 128k \
  -aspect 4:3 \
  -y '$SOURCE_FILE' 2>/dev/null" || {
    echo "ERROR: Failed to generate interlaced test video"
    exit 1
}

# Verify source file was created
if [ ! -f "$SOURCE_FILE" ]; then
    echo "ERROR: Source video not created at $SOURCE_FILE"
    exit 1
fi

# Verify it's actually interlaced
FIELD_ORDER=$(ffprobe -v error -select_streams v:0 -show_entries stream=field_order \
  -of default=noprint_wrappers=1:nokey=1 "$SOURCE_FILE" 2>/dev/null || echo "unknown")

echo "✅ Source video created: $SOURCE_FILE"
echo "   Field order: $FIELD_ORDER"
echo "   Size: $(du -h "$SOURCE_FILE" | cut -f1)"

# Verify file properties
SOURCE_DURATION=$(ffprobe -v error -select_streams v:0 -show_entries format=duration \
  -of default=noprint_wrappers=1:nokey=1 "$SOURCE_FILE" 2>/dev/null || echo "0")
echo "   Duration: ${SOURCE_DURATION}s"

# Set proper permissions
chown ga:ga "$SOURCE_FILE"
chmod 644 "$SOURCE_FILE"

# Clean up any previous output
OUTPUT_FILE="$VIDEO_DIR/family_vhs_1995_deinterlaced.mp4"
rm -f "$OUTPUT_FILE"

# Launch VLC (empty, agent needs to open file and convert)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_deinterlace_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_deinterlace_task.log
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
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Deinterlace Vintage Footage Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SCENARIO: You're helping digitize old family VHS tapes."
echo "  The footage has visible 'combing' artifacts (horizontal lines)"
echo "  when there's movement - this is interlaced video."
echo ""
echo "  YOUR GOAL: Deinterlace and save as progressive video"
echo ""
echo "  STEPS:"
echo "  1. Open the source video:"
echo "     Media → Open File → $SOURCE_FILE"
echo ""
echo "  2. Enable deinterlacing for preview (optional but recommended):"
echo "     Video → Deinterlace → Yadif"
echo "     (or: Tools → Effects and Filters → Video Effects → Deinterlace)"
echo ""
echo "  3. Convert with deinterlacing applied:"
echo "     Media → Convert/Save (Ctrl+R)"
echo "     - Add source: $SOURCE_FILE"
echo "     - Click 'Convert/Save' button"
echo "     - Select profile (e.g., 'Video - H.264 + MP3 (MP4)')"
echo "     - IMPORTANT: Edit profile to ensure deinterlace filter is included"
echo "       (Under 'Video codec' tab → 'Filters' → Check 'Deinterlace')"
echo "     - Set destination: $OUTPUT_FILE"
echo "     - Start conversion"
echo ""
echo "  4. Wait for conversion to complete"
echo ""
echo "  ALTERNATIVE METHOD (CLI for advanced users):"
echo "  Tools → Preferences → Show settings: All"
echo "  → Video → Filters → Deinterlace → Set mode to 'yadif'"
echo "  Then do Media → Convert/Save with deinterlace enabled"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"