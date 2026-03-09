#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Extract Video Segment Task ==="

kill_vlc ga
sleep 1

# Create test video with timestamp overlay (10 minutes long)
VIDEO_FILE="/home/ga/Videos/security_footage.mp4"

if [ ! -f "$VIDEO_FILE" ]; then
    echo "Creating 10-minute test video with timestamp overlay..."
    
    # Generate 10-minute video with timestamp overlay
    # Use testsrc2 for realistic color patterns, add timestamp and visual marker at incident time
    su - ga -c "ffmpeg -f lavfi -i testsrc2=duration=600:size=1280x720:rate=30 \
      -vf \"drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:\
text='Security Footage':x=10:y=10:fontsize=32:fontcolor=white:box=1:boxcolor=black@0.7,\
drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:\
text='%{pts\\\:hms}':x=(w-text_w)/2:y=h-60:fontsize=48:fontcolor=yellow:box=1:boxcolor=black@0.7,\
drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:\
text='INCIDENT':x=(w-text_w)/2:y=(h-text_h)/2:fontsize=72:fontcolor=red:box=1:boxcolor=black@0.8:\
enable='between(t,135,165)'\" \
      -c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p \
      '$VIDEO_FILE' -y > /tmp/ffmpeg_video_gen.log 2>&1"
    
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to generate test video"
        cat /tmp/ffmpeg_video_gen.log
        exit 1
    fi
    
    # Verify video was created
    if [ ! -f "$VIDEO_FILE" ]; then
        echo "ERROR: Video file was not created"
        exit 1
    fi
    
    echo "✅ Test video created: $VIDEO_FILE ($(du -h "$VIDEO_FILE" | cut -f1))"
else
    echo "✅ Test video already exists: $VIDEO_FILE"
fi

# Ensure video is readable
chmod 644 "$VIDEO_FILE"

# Clean up any previous recordings to ensure fresh start
echo "Cleaning up previous recordings..."
rm -f /home/ga/Videos/vlc-record-*.mp4 /home/ga/Videos/vlc-record-*.avi /home/ga/Videos/vlc-record-*.mkv 2>/dev/null || true

# Store task start time for verification
echo "$(date +%s)" > /tmp/vlc_segment_task_start.txt

# Launch VLC with the video
echo "Launching VLC with security footage..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --start-paused '$VIDEO_FILE' > /tmp/vlc_segment_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_segment_task.log || true
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Ensure Advanced Controls are visible (needed for Record button)
echo "Enabling Advanced Controls (for Record button)..."
sleep 1
# Open View menu and enable Advanced Controls
su - ga -c "DISPLAY=:1 xdotool key alt+v" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key a" || true  # 'a' for Advanced Controls
sleep 1

# Give time for UI to update
sleep 1

echo "=== Extract Video Segment Task Setup Complete ==="
echo ""
echo "📝 TASK INSTRUCTIONS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎯 GOAL: Extract the incident segment (02:15 to 02:45) from the video"
echo ""
echo "📹 Source: $VIDEO_FILE (10 minutes)"
echo "🎯 Target segment: 02:15 - 02:45 (30 seconds)"
echo "💾 Output location: /home/ga/Videos/vlc-record-*.mp4"
echo ""
echo "STEPS:"
echo "  1. Navigate to timestamp 02:15 (2 minutes 15 seconds)"
echo "     Methods:"
echo "       - Playback → Jump to Specific Time (Ctrl+T), enter '135' seconds"
echo "       - Click on progress bar at ~1/4 position"
echo "       - Use Shift+Right to jump forward (each press = 5 seconds)"
echo ""
echo "  2. Start Recording"
echo "       - Click the Record button (red circle) in the controls"
echo "       - If not visible: View → Advanced Controls"
echo "       - Button will be highlighted when recording"
echo ""
echo "  3. Play video through the incident (until 02:45)"
echo "       - Press Space to play"
echo "       - Let it play for ~30 seconds"
echo ""
echo "  4. Stop Recording at 02:45"
echo "       - Click Record button again to stop"
echo "       - Recording saves automatically to Videos folder"
echo ""
echo "⏱️  Timing tolerance: ±3 seconds is acceptable"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"