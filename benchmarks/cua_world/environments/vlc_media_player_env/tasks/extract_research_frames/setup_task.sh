#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Extract Research Frames Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Create directories
mkdir -p /home/ga/Videos/research
mkdir -p /home/ga/Pictures/research_frames

# Clean up any existing frames
rm -f /home/ga/Pictures/research_frames/*.png

# Generate a 30-second test video with visual frame markers
# This simulates high-speed footage with distinct frames at each timestamp
echo "Generating test video with frame markers..."
su - ga -c "ffmpeg -f lavfi -i testsrc=duration=30:size=1280x720:rate=30 \
    -vf \"drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='Time\\: %{pts\\\\:hms}':x=50:y=50:fontsize=48:fontcolor=white:box=1:boxcolor=black@0.5,drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='Frame\\: %{frame_num}':x=50:y=150:fontsize=48:fontcolor=yellow:box=1:boxcolor=black@0.5\" \
    -pix_fmt yuv420p -c:v libx264 -preset ultrafast -y /home/ga/Videos/research/motion_study.mp4 2>/dev/null" || {
    echo "ERROR: Failed to generate test video"
    exit 1
}

if [ ! -f /home/ga/Videos/research/motion_study.mp4 ]; then
    echo "ERROR: Test video not created"
    exit 1
fi

echo "✅ Test video created"

# Create instruction file with target timestamps
cat > /home/ga/Videos/research/frame_extraction_targets.txt << 'EOF'
# Frame Extraction Targets for motion_study.mp4
# Extract frames at these timestamps and save with specified filenames
# Format: timestamp_seconds | desired_filename (without .png extension)
#
# Instructions:
# 1. Open motion_study.mp4 in VLC
# 2. For each timestamp below:
#    - Seek to the exact time (use Ctrl+T for "Jump to Time")
#    - Pause the video (Space)
#    - Take a snapshot (Shift+S)
#    - Rename the snapshot to the specified filename
# 3. Save all frames to: /home/ga/Pictures/research_frames/
# 4. Ensure all filenames match exactly (add .png extension)

5.0 | frame_position_01
10.5 | frame_position_02
15.2 | frame_position_03
20.8 | frame_position_04
25.3 | frame_position_05
EOF

# Configure VLC snapshot preferences
mkdir -p /home/ga/.config/vlc
VLC_RC="/home/ga/.config/vlc/vlcrc"

# Backup existing config if present
if [ -f "$VLC_RC" ]; then
    cp "$VLC_RC" "${VLC_RC}.backup"
fi

# Update or create VLC config with snapshot settings
if [ -f "$VLC_RC" ]; then
    # Remove existing snapshot settings
    sed -i '/^snapshot-path=/d' "$VLC_RC"
    sed -i '/^snapshot-format=/d' "$VLC_RC"
    sed -i '/^snapshot-preview=/d' "$VLC_RC"
    sed -i '/^snapshot-sequential=/d' "$VLC_RC"
fi

# Append snapshot settings
cat >> "$VLC_RC" << 'EOF'

# Snapshot settings for research frame extraction
snapshot-path=/home/ga/Pictures/research_frames
snapshot-format=png
snapshot-preview=0
snapshot-sequential=0
EOF

# Set ownership
chown -R ga:ga /home/ga/Videos/research
chown -R ga:ga /home/ga/Pictures/research_frames
chown -R ga:ga /home/ga/.config/vlc

echo "✅ Configuration files created"

# Launch VLC with the research video
echo "Launching VLC with research video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --start-paused /home/ga/Videos/research/motion_study.mp4 > /tmp/vlc_research_frames_task.log 2>&1 &"

# Wait for VLC to start
if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_research_frames_task.log
    exit 1
fi

# Wait for window to appear
if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of screen to select current desktop (should be done in all tasks)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 640 360 click 1" || true
sleep 1

# Focus VLC window
echo "Focusing VLC window..."
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Give VLC time to fully initialize
sleep 2

# Unpause briefly to initialize video output (needed for snapshots to work)
echo "Initializing video output..."
su - ga -c "DISPLAY=:1 xdotool key space" || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key space" || true
sleep 1

# Seek to beginning
su - ga -c "DISPLAY=:1 xdotool key ctrl+Home" || true
sleep 1

echo "=== Extract Research Frames Task Setup Complete ==="
echo ""
echo "📋 Task Instructions:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Video: /home/ga/Videos/research/motion_study.mp4"
echo "Targets: /home/ga/Videos/research/frame_extraction_targets.txt"
echo "Output: /home/ga/Pictures/research_frames/"
echo ""
echo "Required frames to extract:"
echo "  1. frame_position_01.png (from ~5.0s)"
echo "  2. frame_position_02.png (from ~10.5s)"
echo "  3. frame_position_03.png (from ~15.2s)"
echo "  4. frame_position_04.png (from ~20.8s)"
echo "  5. frame_position_05.png (from ~25.3s)"
echo ""
echo "Workflow:"
echo "  1. Seek to timestamp (Ctrl+T for 'Jump to Time')"
echo "  2. Pause if needed (Space)"
echo "  3. Take snapshot (Shift+S)"
echo "  4. Rename file to match target filename"
echo "  5. Repeat for all 5 timestamps"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"