#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Generate Preview Contact Sheet Task ==="

kill_vlc ga
sleep 1

# Create mystery files directory
MYSTERY_DIR="/home/ga/Videos/mystery_files"
mkdir -p "$MYSTERY_DIR"
chown ga:ga "$MYSTERY_DIR"

# Create output directory for contact sheets
OUTPUT_DIR="/home/ga/Pictures/contact_sheets"
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean any existing files in output directory
rm -f "$OUTPUT_DIR"/*.png

echo "Creating mystery video files..."

# Video 1: 30 seconds - Color gradient (red→green→blue→yellow→red)
# This simulates finding an old screen recording or color test
echo "Creating unknown_01.mp4 (30s color gradient)..."
ffmpeg -f lavfi -i "color=c=red:s=640x480:d=6" \
       -f lavfi -i "color=c=green:s=640x480:d=6" \
       -f lavfi -i "color=c=blue:s=640x480:d=6" \
       -f lavfi -i "color=c=yellow:s=640x480:d=6" \
       -f lavfi -i "color=c=red:s=640x480:d=6" \
       -filter_complex "[0:v][1:v][2:v][3:v][4:v]concat=n=5:v=1:a=0[v]" \
       -map "[v]" -t 30 -y "$MYSTERY_DIR/unknown_01.mp4" \
       > /tmp/ffmpeg_video1.log 2>&1

# Video 2: 40 seconds - Incrementing numbers (0, 10, 20, ..., 400)
# Simulates finding old tutorial or presentation recording
echo "Creating unknown_02.mp4 (40s numbers)..."
ffmpeg -f lavfi -i color=c=black:s=640x480:d=40 \
       -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:fontsize=120:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2:text='%{eif\:t*10\:d}'" \
       -t 40 -y "$MYSTERY_DIR/unknown_02.mp4" \
       > /tmp/ffmpeg_video2.log 2>&1

# Video 3: 50 seconds - Geometric shapes (circle, square, triangle, star, pentagon cycle)
# Simulates finding old animation or design file
echo "Creating unknown_03.mp4 (50s shapes)..."
# Create a simple shape sequence (using different colors for each 10s segment)
ffmpeg -f lavfi -i "color=c=0xFF6B6B:s=640x480:d=10" \
       -f lavfi -i "color=c=0x4ECDC4:s=640x480:d=10" \
       -f lavfi -i "color=c=0x45B7D1:s=640x480:d=10" \
       -f lavfi -i "color=c=0xF7DC6F:s=640x480:d=10" \
       -f lavfi -i "color=c=0xBB8FCE:s=640x480:d=10" \
       -filter_complex "[0:v]drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:fontsize=80:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2:text='●'[v0]; \
                        [1:v]drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:fontsize=80:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2:text='■'[v1]; \
                        [2:v]drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:fontsize=80:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2:text='▲'[v2]; \
                        [3:v]drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:fontsize=80:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2:text='★'[v3]; \
                        [4:v]drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:fontsize=80:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2:text='⬟'[v4]; \
                        [v0][v1][v2][v3][v4]concat=n=5:v=1:a=0[v]" \
       -map "[v]" -t 50 -y "$MYSTERY_DIR/unknown_03.mp4" \
       > /tmp/ffmpeg_video3.log 2>&1

# Verify videos were created
for video in unknown_01.mp4 unknown_02.mp4 unknown_03.mp4; do
    if [ ! -f "$MYSTERY_DIR/$video" ]; then
        echo "ERROR: Failed to create $video"
        exit 1
    fi
    
    # Check video is valid
    if ! ffprobe -v error "$MYSTERY_DIR/$video" > /dev/null 2>&1; then
        echo "ERROR: $video is not a valid video file"
        exit 1
    fi
    
    echo "✅ Created $video ($(du -h "$MYSTERY_DIR/$video" | cut -f1))"
done

chown -R ga:ga "$MYSTERY_DIR"

# Launch VLC without any video (agent will decide how to process files)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_contact_sheet_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
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

echo "=== Generate Preview Contact Sheet Task Setup Complete ==="
echo ""
echo "📝 TASK: Generate preview snapshots for quick content identification"
echo ""
echo "Mystery video files (unlabeled - need identification):"
echo "  • $MYSTERY_DIR/unknown_01.mp4 (30 seconds)"
echo "  • $MYSTERY_DIR/unknown_02.mp4 (40 seconds)"
echo "  • $MYSTERY_DIR/unknown_03.mp4 (50 seconds)"
echo ""
echo "📋 Requirements:"
echo "  1. For EACH video, capture 5 preview snapshots at:"
echo "     - 10% through video"
echo "     - 30% through video"
echo "     - 50% through video"
echo "     - 70% through video"
echo "     - 90% through video"
echo ""
echo "  2. Save snapshots to: $OUTPUT_DIR/"
echo ""
echo "  3. Use clear filenames that indicate:"
echo "     - Source video (e.g., unknown_01)"
echo "     - Position (e.g., 10pct, 30pct, or timestamp like 3s, 12s)"
echo ""
echo "  4. Expected output: 15 PNG images total (5 per video)"
echo ""
echo "💡 Suggested approaches:"
echo "  • CLI: Use ffprobe to get duration, calculate timestamps, use cvlc or ffmpeg"
echo "  • GUI: Open each video, seek to positions, press Shift+S for snapshots"
echo "  • Batch: Write a script to process all three videos automatically"
echo ""
echo "Example filename formats (any reasonable format works):"
echo "  • unknown_01_preview_10pct.png"
echo "  • unknown_02_snap_30percent.png"
echo "  • unknown_03_3s.png"