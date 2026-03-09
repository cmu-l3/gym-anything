#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Mirror Dance Video Task ==="

TASK_NAME="mirror_dance_video"
VIDEO_DIR="/home/ga/Videos"
INPUT_FILE="${VIDEO_DIR}/dance_demo.mp4"
OUTPUT_FILE="${VIDEO_DIR}/dance_demo_mirrored.mp4"

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Ensure video directory exists
mkdir -p "${VIDEO_DIR}"
chown ga:ga "${VIDEO_DIR}"

# Remove any previous outputs
rm -f "${OUTPUT_FILE}"

# Generate a 45-second test video in portrait orientation (720x1280)
# This simulates a phone recording that needs rotation and mirroring
echo "[${TASK_NAME}] Generating dance demo video (portrait orientation)..."

# Create a visually distinct test pattern that shows orientation
# Using testsrc with color bars so rotation/flip can be visually verified
ffmpeg -f lavfi -i "testsrc=duration=45:size=720x1280:rate=30" \
    -f lavfi -i "sine=frequency=440:duration=45" \
    -vf "drawtext=text='TOP':fontsize=60:fontcolor=white:x=(w-text_w)/2:y=50:box=1:boxcolor=black@0.5:boxborderw=5,\
         drawtext=text='BOTTOM':fontsize=60:fontcolor=white:x=(w-text_w)/2:y=h-100:box=1:boxcolor=black@0.5:boxborderw=5,\
         drawtext=text='LEFT':fontsize=40:fontcolor=yellow:x=50:y=(h-text_h)/2:box=1:boxcolor=black@0.5:boxborderw=5,\
         drawtext=text='RIGHT':fontsize=40:fontcolor=yellow:x=w-200:y=(h-text_h)/2:box=1:boxcolor=black@0.5:boxborderw=5" \
    -pix_fmt yuv420p -c:v libx264 -preset ultrafast -c:a aac \
    "${INPUT_FILE}" -y 2>/dev/null || {
    echo "[${TASK_NAME}] ERROR: Failed to generate video with text overlay"
    # Fallback: simpler video without text
    ffmpeg -f lavfi -i "testsrc=duration=45:size=720x1280:rate=30" \
        -f lavfi -i "sine=frequency=440:duration=45" \
        -pix_fmt yuv420p -c:v libx264 -preset ultrafast -c:a aac \
        "${INPUT_FILE}" -y 2>/dev/null
}

if [ ! -f "${INPUT_FILE}" ]; then
    echo "[${TASK_NAME}] ERROR: Failed to generate video file"
    exit 1
fi

# Verify video was created
VIDEO_SIZE=$(stat -f%z "${INPUT_FILE}" 2>/dev/null || stat -c%s "${INPUT_FILE}" 2>/dev/null || echo "0")
if [ "$VIDEO_SIZE" -lt 10000 ]; then
    echo "[${TASK_NAME}] ERROR: Generated video is too small (${VIDEO_SIZE} bytes)"
    exit 1
fi

echo "[${TASK_NAME}] Video generated successfully: ${INPUT_FILE} (${VIDEO_SIZE} bytes)"

# Launch VLC with the video file
echo "[${TASK_NAME}] Launching VLC with dance demo video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show '${INPUT_FILE}' > /tmp/vlc_mirror_dance_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "[${TASK_NAME}] ERROR: VLC failed to start"
    cat /tmp/vlc_mirror_dance_task.log 2>/dev/null || true
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "[${TASK_NAME}] ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks)
echo "[${TASK_NAME}] Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Pause video so agent can work on it
echo "[${TASK_NAME}] Pausing video..."
sleep 1
su - ga -c "DISPLAY=:1 xdotool key space" || true
sleep 0.5

echo "=== Mirror Dance Video Task Setup Complete ==="
echo ""
echo "📝 TASK INSTRUCTIONS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "You have a dance instruction video that needs transformation:"
echo ""
echo "  Input:  ${INPUT_FILE}"
echo "  Output: ${OUTPUT_FILE}"
echo ""
echo "REQUIRED TRANSFORMATIONS:"
echo "  1. Rotate 90° CLOCKWISE (portrait → landscape)"
echo "  2. HORIZONTALLY FLIP (mirror for dance instruction)"
echo ""
echo "WORKFLOW:"
echo "  Step 1: Open Effects and Filters"
echo "          → Tools → Effects and Filters (or Ctrl+E)"
echo ""
echo "  Step 2: Go to Video Effects → Geometry tab"
echo ""
echo "  Step 3: Apply Rotation"
echo "          → Check 'Transform' checkbox"
echo "          → Select 'Rotate by 90 degrees' from dropdown"
echo ""
echo "  Step 4: Apply Horizontal Flip"
echo "          → Check additional transform option for mirror/flip"
echo "          → Or use separate 'Mirror' option if available"
echo ""
echo "  Step 5: Preview the transformations (optional)"
echo ""
echo "  Step 6: Convert and Save with Effects"
echo "          → Media → Convert/Save (or Ctrl+R)"
echo "          → Source: ${INPUT_FILE}"
echo "          → Profile: Video - H.264 + MP3 (MP4) or similar"
echo "          → Destination: ${OUTPUT_FILE}"
echo "          → ⚠️  IMPORTANT: Ensure effects are applied!"
echo "          → Click Start and wait for conversion"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"