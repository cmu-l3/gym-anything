#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Scan Security Footage Task ==="

kill_vlc ga
sleep 1

# Create evidence output directory
mkdir -p /home/ga/Pictures/security_evidence
chown ga:ga /home/ga/Pictures/security_evidence

# Configure VLC snapshot settings to use evidence directory
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    sed -i '/^snapshot-path=/d' "$VLC_RC"
    echo "snapshot-path=/home/ga/Pictures/security_evidence" >> "$VLC_RC"
    sed -i '/^snapshot-format=/d' "$VLC_RC"
    echo "snapshot-format=png" >> "$VLC_RC"
fi

# Generate mock security footage video
VIDEO_FILE="/home/ga/Videos/security_overnight_2024-01-15.mp4"

if [ ! -f "$VIDEO_FILE" ]; then
    echo "Generating mock security footage video..."
    
    # Create a 3-minute video with timestamp overlay
    # Timestamp starts at 05:13:00 and increments
    # At 2:30 (150 seconds), which shows 05:15:30, we insert a visual marker
    
    # First, create base static video (empty parking lot scene)
    ffmpeg -f lavfi -i color=c=0x1a1a2e:s=1280x720:r=30 -t 180 \
           -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf:text='SECURITY CAM 01':fontcolor=white:fontsize=24:x=10:y=10, \
                drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf:text='2024-01-15':fontcolor=white:fontsize=20:x=10:y=50, \
                drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf:text='PARKING LOT - REAR':fontcolor=white:fontsize=16:x=10:y=80" \
           -c:v libx264 -preset ultrafast -crf 28 -y /tmp/security_base.mp4 2>/dev/null
    
    # Add timestamp overlay that increments
    # Use drawtext with timecode starting at 05:13:00
    ffmpeg -i /tmp/security_base.mp4 \
           -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf:fontcolor=lime:fontsize=32:x=w-tw-10:y=10:text='%{pts\:hms\:18780}', \
                drawbox=enable='between(t,145,165)':x=400:y=250:w=200:h=150:color=red@0.3:t=fill, \
                drawtext=enable='between(t,145,165)':fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf:text='SUSPICIOUS ACTIVITY':fontcolor=red:fontsize=28:x=(w-text_w)/2:y=h-100" \
           -c:v libx264 -preset ultrafast -crf 23 -y "$VIDEO_FILE" 2>/dev/null
    
    chown ga:ga "$VIDEO_FILE"
    echo "✅ Mock security footage generated: $VIDEO_FILE"
else
    echo "Security footage video already exists"
fi

# Clear any old snapshots
rm -f /home/ga/Pictures/security_evidence/*.png 2>/dev/null || true
rm -f /home/ga/Pictures/vlc/*.png 2>/dev/null || true

# Launch VLC with the security video
echo "Launching VLC with security footage..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --start-paused '$VIDEO_FILE' > /tmp/vlc_security_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_security_task.log 2>/dev/null || true
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

# Let video render for a moment
sleep 2

echo "=== Scan Security Footage Task Setup Complete ==="
echo "📝 Scenario:"
echo "  You received a report of suspicious activity around 3:00 AM (5 hours into recording)"
echo "  The security DVR exported overnight footage: 10 PM - 6 AM (8 hours)"
echo ""
echo "📝 Instructions:"
echo "  1. Navigate to approximately 5:15:00 (5 hours, 15 minutes)"
echo "  2. Increase playback speed to 3-5x for scanning"
echo "  3. Watch for suspicious activity (person/movement)"
echo "  4. When found, return to normal speed"
echo "  5. Capture 2-3 snapshots (Shift+S) during the incident"
echo ""
echo "💡 Tips:"
echo "  - Use timeline seek or Media → Go to Time (Ctrl+T)"
echo "  - Press ']' to increase playback speed"
echo "  - Press '[' to decrease playback speed"
echo "  - Snapshots save to: /home/ga/Pictures/security_evidence/"