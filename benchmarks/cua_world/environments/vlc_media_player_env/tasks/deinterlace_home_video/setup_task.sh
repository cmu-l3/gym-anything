#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Deinterlace Home Video Task ==="

# Kill any existing VLC instances
kill_vlc ga

sleep 1

# Ensure Videos directory exists
mkdir -p /home/ga/Videos
chown ga:ga /home/ga/Videos

# Generate interlaced test video with clear motion to show combing artifacts
echo "Generating interlaced home video with motion artifacts..."

# Create a video with horizontal moving object to trigger visible combing
# Using field order to create true interlacing that will show scan line artifacts
ffmpeg -f lavfi -i "color=c=blue:s=720x480:d=20:r=30000/1001" \
  -vf "drawbox=x='if(gte(t,0),mod(t*100,w-150),0)':y=(h-80)/2:w=150:h=80:color=white:t=fill,\
       drawtext=text='FAMILY VACATION 1998':fontsize=36:fontcolor=black:x='if(gte(t,0),mod(t*100,w-450),20)':y=(h-th)/2:fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf,\
       drawtext=text='Look for scan lines during motion':fontsize=18:fontcolor=yellow:x=20:y=h-60:fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf,\
       setfield=tff,\
       fieldorder=tff,\
       interlace" \
  -c:v ffv1 -level 3 -pix_fmt yuv420p \
  -r 30000/1001 -flags +ilme+ildct \
  /home/ga/Videos/family_vacation_1998.avi -y 2>/dev/null || {
    echo "⚠️ Detailed interlacing failed, using simpler method..."
    # Fallback: Create simpler interlaced video
    ffmpeg -f lavfi -i "testsrc=duration=20:size=720x480:rate=30" \
      -vf "setfield=tff,fieldorder=tff,interlace" \
      -c:v ffv1 -pix_fmt yuv420p \
      /home/ga/Videos/family_vacation_1998.avi -y 2>/dev/null
  }

# Verify file was created
if [ ! -f /home/ga/Videos/family_vacation_1998.avi ]; then
    echo "ERROR: Failed to create test video"
    exit 1
fi

echo "✅ Interlaced video created: $(du -h /home/ga/Videos/family_vacation_1998.avi | cut -f1)"

# Set proper ownership
chown ga:ga /home/ga/Videos/family_vacation_1998.avi

# Reset VLC configuration to ensure deinterlacing is OFF initially
VLC_CONFIG_DIR="/home/ga/.config/vlc"
VLC_RC="$VLC_CONFIG_DIR/vlcrc"

mkdir -p "$VLC_CONFIG_DIR"

# Remove any existing deinterlacing settings
if [ -f "$VLC_RC" ]; then
    sed -i '/^deinterlace=/d' "$VLC_RC"
    sed -i '/^deinterlace-mode=/d' "$VLC_RC"
    sed -i '/^sout-deinterlace-mode=/d' "$VLC_RC"
    echo "Cleared existing deinterlacing settings"
fi

# Ensure deinterlacing is explicitly disabled
cat >> "$VLC_RC" << 'EOF'

# Deinterlacing should be OFF for this task
deinterlace=0
deinterlace-mode=disabled
EOF

# Also clear Qt interface config
rm -f "$VLC_CONFIG_DIR/vlc-qt-interface.conf" 2>/dev/null || true

chown -R ga:ga "$VLC_CONFIG_DIR"

echo "VLC config reset - deinterlacing disabled"

# Launch VLC with RC interface enabled
echo "Launching VLC with interlaced video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop --extraintf rc --rc-host localhost:9999 /home/ga/Videos/family_vacation_1998.avi > /tmp/vlc_deinterlace_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_deinterlace_task.log 2>/dev/null || true
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Wait for RC interface to be ready
echo "Waiting for RC interface..."
for i in {1..10}; do
    if echo "info" | nc -w 1 localhost 9999 > /dev/null 2>&1; then
        echo "RC interface ready"
        break
    fi
    if [ $i -eq 10 ]; then
        echo "⚠️ RC interface not responding"
    fi
    sleep 1
done

# Click on center of the screen to select current desktop (should be done in all tasks)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    echo "VLC window focused (WID: $wid)"
else
    echo "⚠️ Could not get VLC window ID"
fi

# Let video play for a moment to show the interlacing artifacts
sleep 2

echo "=== Deinterlace Home Video Task Setup Complete ==="
echo ""
echo "📺 TASK INSTRUCTIONS:"
echo "═══════════════════════════════════════════════════"
echo "  Video: /home/ga/Videos/family_vacation_1998.avi"
echo ""
echo "  PROBLEM: The video has visible 'combing' artifacts"
echo "           (horizontal scan lines during motion)"
echo ""
echo "  SOLUTION: Enable deinterlacing in VLC"
echo ""
echo "  Method 1 (Recommended):"
echo "    1. Click 'Video' menu → 'Deinterlace'"
echo "    2. Select a mode: 'Yadif' (best quality)"
echo "    3. Watch the video - combing should disappear"
echo ""
echo "  Method 2 (Keyboard):"
echo "    1. Press 'D' key repeatedly to cycle modes"
echo "    2. Stop when artifacts disappear"
echo ""
echo "  Method 3 (Preferences):"
echo "    1. Tools → Preferences"
echo "    2. Show settings: All (bottom left)"
echo "    3. Video → Filters → Deinterlacing"
echo "    4. Enable and select mode"
echo "═══════════════════════════════════════════════════"