#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Record Synchronized Commentary Task ==="

# Kill any existing VLC instances
kill_vlc ga

sleep 1

# Create directories
mkdir -p /home/ga/Videos/recorded_commentary
mkdir -p /home/ga/Pictures/vlc
chown -R ga:ga /home/ga/Videos/recorded_commentary
chown -R ga:ga /home/ga/Pictures/vlc

# Generate a 3-minute test video with timecode overlay (simulates game footage)
GAME_VIDEO="/home/ga/Videos/game_footage.mp4"

if [ ! -f "$GAME_VIDEO" ]; then
    echo "Generating test game footage video with timecode..."
    
    # Create a video with moving color gradient and timecode
    su - ga -c "ffmpeg -f lavfi -i 'color=c=0x228B22:s=1280x720:d=180' \
      -f lavfi -i 'color=c=0x4169E1:s=1280x720:d=180' \
      -filter_complex \"\
        [0:v][1:v]blend=all_mode=multiply:all_opacity=0.5[bg]; \
        [bg]drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:\
text='GAME FOOTAGE':fontsize=64:fontcolor=white:x=(w-text_w)/2:y=80:box=1:boxcolor=black@0.5:boxborderw=10[txt1]; \
        [txt1]drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:\
text='%{pts\\\\:hms}':fontsize=48:fontcolor=yellow:x=(w-text_w)/2:y=(h-text_h)/2[txt2]; \
        [txt2]drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:\
text='Record commentary while watching':fontsize=24:fontcolor=white:x=(w-text_w)/2:y=h-100\" \
      -c:v libx264 -preset fast -crf 23 -t 180 -pix_fmt yuv420p -y '$GAME_VIDEO' \
      > /tmp/vlc_video_gen.log 2>&1" || {
        echo "ERROR: Failed to generate test video"
        cat /tmp/vlc_video_gen.log
        exit 1
    }
    
    echo "✅ Test video created: $GAME_VIDEO"
else
    echo "✅ Test video already exists: $GAME_VIDEO"
fi

# Verify video was created successfully
if [ ! -f "$GAME_VIDEO" ] || [ ! -s "$GAME_VIDEO" ]; then
    echo "ERROR: Game footage video is missing or empty"
    exit 1
fi

# Configure VLC for recording
VLC_CONFIG="/home/ga/.config/vlc/vlcrc"
mkdir -p "$(dirname "$VLC_CONFIG")"

# Set recording preferences
if [ -f "$VLC_CONFIG" ]; then
    # Remove old recording settings
    sed -i '/^input-record-path=/d' "$VLC_CONFIG"
    sed -i '/^input-record-native=/d' "$VLC_CONFIG"
    sed -i '/^sout-record-dst-prefix=/d' "$VLC_CONFIG"
fi

# Add recording configuration
cat >> "$VLC_CONFIG" << 'EOF'

# Recording configuration for commentary task
[core]
input-record-path=/home/ga/Videos/recorded_commentary/
input-record-native=0

# Snapshot configuration
[video]
snapshot-path=/home/ga/Pictures/vlc
snapshot-format=png

# Show advanced controls by default
[qt]
qt-advanced-buttons=1

EOF

chown ga:ga "$VLC_CONFIG"
echo "✅ VLC recording configuration updated"

# Setup PulseAudio dummy source (simulates microphone for testing)
echo "Setting up audio environment..."
su - ga -c "DISPLAY=:1 pulseaudio --check" || su - ga -c "DISPLAY=:1 pulseaudio --start" || true
sleep 1

# Create task start marker for finding newly created files
touch /tmp/task_start_marker

# Launch VLC with the game footage
echo "Launching VLC with game footage..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc \
    --avcodec-hw=none \
    --no-video-title-show \
    --loop \
    --start-paused \
    '$GAME_VIDEO' \
    > /tmp/vlc_commentary_task.log 2>&1 &"

# Wait for VLC to start
if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_commentary_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 640 360 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    echo "✅ VLC window focused (WID: $wid)"
fi

# Give VLC time to fully initialize
sleep 2

echo ""
echo "=== Record Synchronized Commentary Task Setup Complete ==="
echo ""
echo "📝 TASK INSTRUCTIONS:"
echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  1. Enable Advanced Controls:"
echo "     → View menu → Advanced Controls"
echo "     → This shows the record button (red circle) in control bar"
echo ""
echo "  2. Start Recording:"
echo "     → Click the red RECORD button (appears in control bar)"
echo "     → Button will become pressed/highlighted when recording"
echo ""
echo "  3. Start Playback:"
echo "     → Press SPACE or click Play button"
echo "     → Video will play while recording"
echo ""
echo "  4. Record for at least 2 minutes (120 seconds)"
echo "     → Watch the timecode on screen"
echo "     → Let it play to at least 00:02:00"
echo ""
echo "  5. Stop Recording:"
echo "     → Click the RECORD button again to stop"
echo "     → File will be saved automatically"
echo ""
echo "  OUTPUT: Audio file will be saved to:"
echo "    • /home/ga/Videos/recorded_commentary/"
echo "    • or /home/ga/Videos/"
echo ""
echo "  TIPS:"
echo "    • Record button is in the BOTTOM control bar"
echo "    • You can pause/resume playback while recording"
echo "    • Alternative: Media → Convert/Save for advanced options"
echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Create instruction file
cat > /home/ga/Videos/RECORDING_TASK.txt << 'EOF'
TASK: Record Synchronized Audio Commentary

Goal: Record audio commentary while playing the game footage video

Steps:
1. Enable Advanced Controls (View → Advanced Controls)
2. Click the red RECORD button before playing
3. Press SPACE to start playback
4. Record for at least 2 minutes
5. Click RECORD button again to stop

Expected Output:
- Audio file in /home/ga/Videos/recorded_commentary/
- Filename may be: commentary_*, vlc-record-*, or similar
- Duration: ~120-180 seconds
- Size: >200KB

Video Information:
- Source: /home/ga/Videos/game_footage.mp4
- Duration: 3 minutes (180 seconds)
- Timecode shown on screen for reference
EOF

chown ga:ga /home/ga/Videos/RECORDING_TASK.txt

echo "✅ Setup complete - VLC ready for recording task"