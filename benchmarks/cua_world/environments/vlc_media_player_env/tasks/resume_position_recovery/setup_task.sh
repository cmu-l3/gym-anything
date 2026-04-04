#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Resume Position Recovery Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Ensure output directories exist
mkdir -p /home/ga/Videos
mkdir -p /home/ga/.local/share/vlc
mkdir -p /home/ga/.config/vlc
mkdir -p /home/ga/.cache/vlc

# Generate a 90-minute documentary-style video
# Use test pattern with timestamps burned in for visual verification
# Using ultrafast preset and low quality for quick generation
VIDEO_FILE="/home/ga/Videos/documentary_urban_planning.mp4"

if [ ! -f "$VIDEO_FILE" ]; then
    echo "Generating 90-minute documentary video (this may take 2-3 minutes)..."
    
    # Generate 90-minute video (5400 seconds) with:
    # - Test source pattern at 5fps (low CPU usage)
    # - 640x480 resolution
    # - Ultrafast encoding preset
    # - Low quality (high CRF) for smaller file size
    # - Simple audio tone
    
    ffmpeg -y \
        -f lavfi -i testsrc=duration=5400:size=640x480:rate=5 \
        -f lavfi -i sine=frequency=440:duration=5400 \
        -c:v libx264 -preset ultrafast -crf 35 -tune fastdecode \
        -c:a aac -b:a 64k -ar 22050 \
        -metadata title="Urban Planning Documentary: Transportation Systems" \
        -metadata comment="90-minute documentary about urban development" \
        "$VIDEO_FILE" 2>/tmp/vlc_task_setup.log || {
            echo "ERROR: Failed to generate documentary video"
            cat /tmp/vlc_task_setup.log
            exit 1
        }
    
    # Verify video was created and has reasonable size
    if [ ! -f "$VIDEO_FILE" ]; then
        echo "ERROR: Video file not created"
        exit 1
    fi
    
    VIDEO_SIZE=$(stat -c%s "$VIDEO_FILE" 2>/dev/null || stat -f%z "$VIDEO_FILE" 2>/dev/null || echo "0")
    echo "✓ Documentary video created: $(numfmt --to=iec-i --suffix=B $VIDEO_SIZE 2>/dev/null || echo "${VIDEO_SIZE} bytes")"
else
    echo "✓ Documentary video already exists"
fi

# Reset VLC's recent media and playback history to ensure clean state
echo "Clearing VLC playback history..."
rm -f /home/ga/.local/share/vlc/ml.xspf 2>/dev/null || true
rm -f /home/ga/.local/share/vlc/vlc-media-library.db* 2>/dev/null || true
rm -rf /home/ga/.cache/vlc/* 2>/dev/null || true

# Reset VLC configuration to default state
# Set qt-continue to 2 (never resume) initially - agent needs to change this
echo "Resetting VLC configuration to default state..."
cat > /home/ga/.config/vlc/vlcrc << 'EOF'
# VLC media player configuration

[qt]
qt-privacy-ask=0
qt-continue=2
qt-recentplay=1
qt-updates-notif=0

[core]
metadata-network-access=0

[snapshot]
snapshot-path=/home/ga/Pictures/vlc
snapshot-format=png
EOF

# Set proper permissions
chown -R ga:ga /home/ga/Videos
chown -R ga:ga /home/ga/.config/vlc
chown -R ga:ga /home/ga/.local/share/vlc
chown -R ga:ga /home/ga/.cache/vlc

# Launch VLC without any video initially
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_resume_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_resume_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 640 400 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

sleep 1

echo "=== Resume Position Recovery Task Setup Complete ==="
echo ""
echo "📋 Task Instructions:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Enable resume playback in VLC settings:"
echo "   • Tools → Preferences (Ctrl+P)"
echo "   • Interface section → 'Continue playback?' setting"
echo "   • Change from 'Never' to 'Ask' or 'Always'"
echo "   • Save preferences"
echo ""
echo "2. Open the documentary:"
echo "   • Media → Open File (Ctrl+O)"
echo "   • Navigate to: /home/ga/Videos/documentary_urban_planning.mp4"
echo "   • Open the file"
echo ""
echo "3. Seek to approximately 47 minutes:"
echo "   • Method A: Click progress bar at 47/90 position"
echo "   • Method B: Use Ctrl+Right to jump 1 minute at a time"
echo "   • Method C: Playback → Jump to Time (Ctrl+T) → Enter '47:00'"
echo "   • Target: 47:00 ± 30 seconds"
echo ""
echo "4. Close VLC properly:"
echo "   • Use Ctrl+Q or Media → Quit"
echo "   • This ensures position is saved"
echo ""
echo "📝 Video location: /home/ga/Videos/documentary_urban_planning.mp4"
echo "📝 Target position: 47:00 (2820 seconds)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"