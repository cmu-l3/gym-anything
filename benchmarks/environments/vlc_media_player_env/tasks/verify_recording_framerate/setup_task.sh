#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Verify Recording Framerate Task ==="

TASK_DIR="/workspace/tasks/verify_recording_framerate"
USER_HOME="/home/ga"
VIDEOS_DIR="${USER_HOME}/Videos"
RECORDING_FILE="${VIDEOS_DIR}/gameplay_recording.mp4"

log_task() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a /tmp/vlc_task_verify_recording.log
}

# Kill any existing VLC instances
kill_vlc ga
sleep 1

log_task "Setting up verify_recording_framerate task..."

# Ensure videos directory exists
mkdir -p "${VIDEOS_DIR}"
chown -R ga:ga "${VIDEOS_DIR}"

# Generate a test gameplay recording with KNOWN characteristics
# - 60 FPS constant frame rate
# - 10 seconds duration
# - 1920x1080 resolution
# - Simulated "game-like" content (moving patterns)

log_task "Generating test gameplay recording..."

# Check if ffmpeg is available
if ! command -v ffmpeg &> /dev/null; then
    log_task "ERROR: ffmpeg not found, installing..."
    apt-get update && apt-get install -y ffmpeg
fi

# Generate test video with testsrc pattern (looks like game graphics)
su - ga -c "cd ${VIDEOS_DIR} && ffmpeg -f lavfi \
    -i testsrc=size=1920x1080:rate=60:duration=10 \
    -pix_fmt yuv420p \
    -c:v libx264 \
    -preset ultrafast \
    -tune zerolatency \
    -crf 18 \
    -g 120 \
    -r 60 \
    -movflags +faststart \
    -y gameplay_recording.mp4 2>&1 | tee -a /tmp/vlc_task_verify_recording.log"

# Verify recording was created successfully
if [ ! -f "${RECORDING_FILE}" ]; then
    log_task "ERROR: Failed to generate gameplay recording"
    exit 1
fi

# Get actual file properties for verification
ACTUAL_FPS=$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=r_frame_rate \
    -of default=noprint_wrappers=1:nokey=1 \
    "${RECORDING_FILE}" 2>/dev/null | head -n1)

ACTUAL_DURATION=$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=duration \
    -of default=noprint_wrappers=1:nokey=1 \
    "${RECORDING_FILE}" 2>/dev/null | head -n1)

ACTUAL_WIDTH=$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=width \
    -of default=noprint_wrappers=1:nokey=1 \
    "${RECORDING_FILE}" 2>/dev/null | head -n1)

ACTUAL_HEIGHT=$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=height \
    -of default=noprint_wrappers=1:nokey=1 \
    "${RECORDING_FILE}" 2>/dev/null | head -n1)

log_task "Generated recording properties:"
log_task "  - File: ${RECORDING_FILE}"
log_task "  - FPS: ${ACTUAL_FPS}"
log_task "  - Duration: ${ACTUAL_DURATION}s"
log_task "  - Resolution: ${ACTUAL_WIDTH}x${ACTUAL_HEIGHT}"

# Store ground truth for verifier
cat > /tmp/recording_ground_truth.json <<EOF
{
    "filepath": "${RECORDING_FILE}",
    "expected_fps": "${ACTUAL_FPS}",
    "expected_duration": ${ACTUAL_DURATION},
    "expected_width": ${ACTUAL_WIDTH},
    "expected_height": ${ACTUAL_HEIGHT},
    "expected_frame_count": 600,
    "is_cfr": true
}
EOF

log_task "Ground truth saved to /tmp/recording_ground_truth.json"

# Launch VLC with the recording
log_task "Launching VLC with gameplay recording..."

su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --start-paused '${RECORDING_FILE}' > /tmp/vlc_framerate_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    log_task "ERROR: VLC failed to start"
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    log_task "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks)
log_task "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Wait for VLC to fully initialize
sleep 2

log_task "=== Verify Recording Framerate Task Setup Complete ==="
log_task "📝 Instructions:"
log_task "  1. Analyze the gameplay recording: ${RECORDING_FILE}"
log_task "  2. Use VLC's diagnostic tools to check frame rate:"
log_task "     - Tools → Media Information (Ctrl+I) → Codec Details tab"
log_task "     - Tools → Messages (Ctrl+M) for debug log"
log_task "  3. Verify recording has consistent 60 FPS"
log_task "  4. Save diagnostic information to a text file:"
log_task "     - ${VIDEOS_DIR}/recording_analysis.txt"
log_task "     - or ${VIDEOS_DIR}/framerate_analysis.txt"
log_task "     - or any .txt/.log file with the analysis"