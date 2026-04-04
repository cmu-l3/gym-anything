#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up A-B Loop Practice Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Ensure Videos directory exists
mkdir -p /home/ga/Videos
chown ga:ga /home/ga/Videos

# Generate practice video with timestamp overlay and dialogue text
echo "Generating practice video with timestamps..."
VIDEO_FILE="/home/ga/Videos/dialogue_practice.mp4"

if [ ! -f "$VIDEO_FILE" ]; then
    # Create 2-minute video with blue background and timestamp overlay
    # Add dialogue text at 42-49 second mark
    ffmpeg -f lavfi -i color=c=blue:s=1280x720:d=120 -f lavfi -i anoisesrc=d=120:c=pink:r=48000:a=0.1 \
        -filter_complex "[0:v]drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='Practice Dialogue Video':fontcolor=white:fontsize=56:x=(w-text_w)/2:y=h/4,\
drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='%{pts\:hms}':fontcolor=yellow:fontsize=48:x=(w-text_w)/2:y=h/2,\
drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='\"The answer lies in the details\"':fontcolor=cyan:fontsize=40:x=(w-text_w)/2:y=2*h/3:enable='between(t,42,49)'[v]" \
        -map "[v]" -map 1:a -c:v libx264 -preset fast -crf 23 -c:a aac -b:a 128k \
        -pix_fmt yuv420p "$VIDEO_FILE" -y 2>/dev/null

    chown ga:ga "$VIDEO_FILE"
    echo "✅ Practice video created: $VIDEO_FILE"
else
    echo "✅ Practice video already exists"
fi

# Create instruction file for the agent
cat > /home/ga/dialogue_segment.txt << 'EOF'
=================================================
        A-B LOOP PRACTICE TASK
=================================================

TARGET SEGMENT FOR PRACTICE LOOP:
  Start: approximately 00:42 (42 seconds)
  End: approximately 00:49 (49 seconds)
  Duration: ~7 seconds
  
DIALOGUE: "The answer lies in the details"
  (visible on screen during this segment)

YOUR TASK:
  Set up VLC to continuously loop ONLY this segment
  so it can be practiced repeatedly without manual rewinding.

INSTRUCTIONS:
  1. Navigate to 42 seconds in the video
  2. Set the loop START point (A)
  3. Navigate to 49 seconds  
  4. Set the loop END point (B)
  5. Verify the loop is active (video should auto-repeat)

METHODS TO SET A-B LOOP:
  • KEYBOARD (Recommended): Press Shift+L twice
    - First press: sets point A (start)
    - Second press: sets point B (end)
  
  • MENU: Playback → A→B Loop
  
  • ADVANCED CONTROLS: View → Advanced Controls
    (shows loop button on interface)

NAVIGATION SHORTCUTS:
  • Click on timeline to seek directly
  • Shift+Right: Jump forward 5 seconds
  • Shift+Left: Jump backward 5 seconds
  • Ctrl+T: Open "Jump to Time" dialog

VERIFICATION:
  After setting up the loop, create a confirmation file:
  
  /tmp/ab_loop_confirmation.txt
  
  With content:
  Loop start: [your A value in seconds]
  Loop end: [your B value in seconds]
  
  Example:
  Loop start: 42.0
  Loop end: 49.0

=================================================
EOF

chown ga:ga /home/ga/dialogue_segment.txt

# Display instructions for logging
echo ""
echo "=== TASK INSTRUCTIONS ==="
cat /home/ga/dialogue_segment.txt
echo "=========================="
echo ""

# Clean up any old confirmation files
rm -f /tmp/ab_loop_confirmation.txt

# Launch VLC with the video
echo "Launching VLC with practice video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --no-loop --no-repeat --start-paused '$VIDEO_FILE' > /tmp/vlc_ab_loop_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_ab_loop_task.log
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

# Wait for video to load
sleep 2

# Open the instruction file in a text editor for agent visibility
echo "Opening instruction file..."
su - ga -c "DISPLAY=:1 gedit /home/ga/dialogue_segment.txt > /dev/null 2>&1 &" || \
su - ga -c "DISPLAY=:1 mousepad /home/ga/dialogue_segment.txt > /dev/null 2>&1 &" || \
su - ga -c "DISPLAY=:1 xed /home/ga/dialogue_segment.txt > /dev/null 2>&1 &" || \
echo "⚠️ Could not open text editor, instructions in /home/ga/dialogue_segment.txt"

sleep 1

# Refocus VLC
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo ""
echo "=== A-B Loop Practice Task Setup Complete ==="
echo "📝 Agent should now:"
echo "  1. Read instructions from /home/ga/dialogue_segment.txt"
echo "  2. Set A-B loop for segment 42-49 seconds"
echo "  3. Create confirmation file: /tmp/ab_loop_confirmation.txt"
echo ""