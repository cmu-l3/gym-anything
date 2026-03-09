#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Concatenate Video Clips Task ==="

kill_vlc ga
sleep 1

# Create directory for clips
CLIPS_DIR="/home/ga/Videos/concat_clips"
mkdir -p "$CLIPS_DIR"
chown -R ga:ga "$CLIPS_DIR"

# Ensure output directory exists
mkdir -p /home/ga/Videos
chown -R ga:ga /home/ga/Videos

# Remove any previous output
rm -f /home/ga/Videos/merged_output.mp4

echo "Generating 4 video clips with distinct visual content..."

# Colors for each clip
COLORS=("red" "green" "blue" "yellow")

# Generate 4 clips with different colors and text overlays
for i in {1..4}; do
    CLIP_NUM=$(printf "%02d" $i)
    COLOR=${COLORS[$((i-1))]}
    
    echo "Creating clip_${CLIP_NUM}.mp4 with ${COLOR} background..."
    
    # Generate 10-second clip with colored background and text
    ffmpeg -y \
        -f lavfi -i "color=c=${COLOR}:s=1280x720:d=10:r=30" \
        -vf "drawtext=text='Clip ${i}':fontsize=120:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2" \
        -c:v libx264 -preset ultrafast -crf 23 \
        -pix_fmt yuv420p \
        -t 10 \
        "${CLIPS_DIR}/clip_${CLIP_NUM}.mp4" \
        > /tmp/ffmpeg_clip_${i}.log 2>&1
    
    if [ ! -f "${CLIPS_DIR}/clip_${CLIP_NUM}.mp4" ]; then
        echo "ERROR: Failed to create clip_${CLIP_NUM}.mp4"
        cat /tmp/ffmpeg_clip_${i}.log
        exit 1
    fi
    
    echo "✅ Created clip_${CLIP_NUM}.mp4 ($(du -h ${CLIPS_DIR}/clip_${CLIP_NUM}.mp4 | cut -f1))"
done

# Verify all clips exist
CLIP_COUNT=$(ls -1 "${CLIPS_DIR}"/clip_*.mp4 2>/dev/null | wc -l)
if [ "$CLIP_COUNT" -ne 4 ]; then
    echo "ERROR: Expected 4 clips, found $CLIP_COUNT"
    exit 1
fi

echo "✅ All 4 clips generated successfully"
ls -lh "${CLIPS_DIR}"/

# Launch VLC (empty, no file loaded)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_concat_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_concat_task.log
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

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

sleep 2

echo "=== Concatenate Video Clips Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Your task: Merge 4 video clips into a single continuous video file."
echo ""
echo "Source clips location: ${CLIPS_DIR}/"
echo "  - clip_01.mp4 (10s, red background)"
echo "  - clip_02.mp4 (10s, green background)"
echo "  - clip_03.mp4 (10s, blue background)"
echo "  - clip_04.mp4 (10s, yellow background)"
echo ""
echo "Output destination: /home/ga/Videos/merged_output.mp4"
echo ""
echo "Method 1 - GUI (Recommended):"
echo "  1. Open: Media → Convert/Save (or press Ctrl+R)"
echo "  2. Click 'Add' button and select all 4 clips IN ORDER"
echo "     (Navigate to ${CLIPS_DIR}/)"
echo "  3. Click 'Convert/Save' button at bottom"
echo "  4. In Profile dropdown, select 'Video - H.264 + MP3 (MP4)'"
echo "  5. Click 'Browse' to set destination file:"
echo "     /home/ga/Videos/merged_output.mp4"
echo "  6. Click 'Start' to begin conversion"
echo "  7. Wait for progress bar to complete"
echo ""
echo "Method 2 - Command Line (Advanced):"
echo "  Open terminal and run:"
echo "  vlc ${CLIPS_DIR}/clip_01.mp4 ${CLIPS_DIR}/clip_02.mp4 \\"
echo "      ${CLIPS_DIR}/clip_03.mp4 ${CLIPS_DIR}/clip_04.mp4 \\"
echo "      --sout '#gather:std{access=file,mux=mp4,dst=/home/ga/Videos/merged_output.mp4}' \\"
echo "      vlc://quit"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"