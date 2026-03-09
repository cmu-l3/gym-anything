#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Optimize Battery Playback Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Ensure VLC config directory exists
mkdir -p /home/ga/.config/vlc
chown -R ga:ga /home/ga/.config/vlc

# Reset VLC to default CPU-intensive settings
echo "Resetting VLC configuration to default (CPU-intensive) settings..."
cat > /home/ga/.config/vlc/vlcrc << 'EOF'
# VLC configuration - Default settings (CPU-intensive)
# This file simulates a fresh VLC install with no optimizations

[core]
# Software decoding (CPU intensive) - this is what we want the agent to change
avcodec-hw=none

# No loop filter skipping (more CPU usage)
avcodec-skiploopfilter=0

# Video filters (if any would consume CPU)
video-filter=
vout-filter=

# Deinterlacing settings
deinterlace=0
deinterlace-mode=auto

# Video output
vout=

# Interface
qt-privacy-ask=0
EOF

chown ga:ga /home/ga/.config/vlc/vlcrc
chmod 644 /home/ga/.config/vlc/vlcrc

echo "✅ VLC config reset to default (software decoding enabled)"

# Ensure Videos directory exists
mkdir -p /home/ga/Videos
chown -R ga:ga /home/ga/Videos

# Create a sample "long video" file if it doesn't exist
# This simulates a training video (2 min sample for testing, named to suggest longer content)
TRAINING_VIDEO="/home/ga/Videos/training_video_long.mp4"

if [ ! -f "$TRAINING_VIDEO" ]; then
    echo "Creating sample training video (2min for testing)..."
    
    # Generate a test video with some visual content
    # Use testsrc for visual pattern, duration 120 seconds
    ffmpeg -loglevel error -f lavfi \
        -i testsrc=duration=120:size=1280x720:rate=30 \
        -f lavfi -i sine=frequency=440:duration=120 \
        -c:v libx264 -preset medium -crf 23 \
        -c:a aac -b:a 128k \
        -y "$TRAINING_VIDEO" 2>/dev/null || {
            echo "⚠️ Could not create sample video with ffmpeg, using existing sample"
            # Fallback: copy existing sample if available
            if [ -f /home/ga/Videos/sample_video.mp4 ]; then
                cp /home/ga/Videos/sample_video.mp4 "$TRAINING_VIDEO"
            fi
        }
    
    chown ga:ga "$TRAINING_VIDEO"
    echo "✅ Training video created: $TRAINING_VIDEO"
fi

# Create instruction file on desktop for the agent
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/BATTERY_OPTIMIZATION_TASK.txt << 'EOF'
⚡ BATTERY OPTIMIZATION TASK ⚡

SCENARIO:
You're on a long flight and need to watch a 4-hour training video.
Your laptop battery is draining too fast with current VLC settings.
VLC is using SOFTWARE decoding which consumes 60-80% CPU!

GOAL:
Configure VLC for efficient playback to maximize battery life.

REQUIRED STEPS:
1. Open VLC Preferences
   - Menu: Tools → Preferences (or press Ctrl+P)

2. Switch to "All" settings mode
   - Look for "Show settings" section at bottom-left
   - Click "All" radio button (not "Simple")

3. Enable Hardware Acceleration
   - Navigate to: Input / Codecs
   - Find "Hardware-accelerated decoding"
   - Change from "Disable" to "Automatic" or "VA-API" (for Linux)

4. Optimize H.264 Decoding (Optional but recommended)
   - In Input / Codecs section
   - Find "Skip H.264 in-loop deblocking filter"
   - Set to "All" for maximum CPU savings

5. Disable Video Filters (if any are enabled)
   - Navigate to: Video → Filters
   - Ensure all filter checkboxes are UNCHECKED

6. Save Settings
   - Click "Save" button at bottom
   - VLC may prompt to restart - allow it

TEST VIDEO: /home/ga/Videos/training_video_long.mp4

VERIFICATION:
After saving, your changes should significantly reduce CPU usage.
Hardware decoding can reduce CPU load by 40-60%!

HINTS:
- The preferences window has a tree on the left side
- "All" settings reveals many more options than "Simple"
- Hardware acceleration is the most critical setting
- Don't worry about perfect optimization, focus on hardware acceleration first
EOF

chown ga:ga /home/ga/Desktop/BATTERY_OPTIMIZATION_TASK.txt
chmod 644 /home/ga/Desktop/BATTERY_OPTIMIZATION_TASK.txt

echo "✅ Task instruction file created: /home/ga/Desktop/BATTERY_OPTIMIZATION_TASK.txt"

# Launch VLC (WITHOUT hardware acceleration to demonstrate the problem)
echo "Launching VLC with current (unoptimized) settings..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_battery_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_battery_task.log 2>/dev/null || true
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
    echo "✅ VLC window focused"
fi

# Wait a moment for window to stabilize
sleep 2

echo "=== Optimize Battery Playback Task Setup Complete ==="
echo ""
echo "📋 Task Summary:"
echo "  • VLC is running with SOFTWARE decoding (CPU intensive)"
echo "  • Agent must enable HARDWARE acceleration"
echo "  • Instructions available at: ~/Desktop/BATTERY_OPTIMIZATION_TASK.txt"
echo "  • Test video: $TRAINING_VIDEO"
echo ""
echo "🎯 Agent should:"
echo "  1. Open Preferences (Ctrl+P)"
echo "  2. Switch to 'All' settings"
echo "  3. Enable hardware acceleration in Input/Codecs"
echo "  4. Save and apply settings"