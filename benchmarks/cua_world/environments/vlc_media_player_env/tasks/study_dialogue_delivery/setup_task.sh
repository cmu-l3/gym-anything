#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Study Dialogue Delivery Task ==="

kill_vlc ga
sleep 1

# Create voice acting reference directory
mkdir -p /home/ga/Pictures/voice_acting_reference
chown -R ga:ga /home/ga/Pictures/voice_acting_reference

# Clear any existing snapshots in the directory
rm -f /home/ga/Pictures/voice_acting_reference/*.png 2>/dev/null || true

# Configure VLC snapshot settings via vlcrc
VLC_RC="/home/ga/.config/vlc/vlcrc"
mkdir -p /home/ga/.config/vlc
chown -R ga:ga /home/ga/.config/vlc

# Pre-configure snapshot settings to encourage correct setup
if [ -f "$VLC_RC" ]; then
    # Reset snapshot settings to defaults
    sed -i '/^snapshot-path=/d' "$VLC_RC"
    sed -i '/^snapshot-format=/d' "$VLC_RC"
    sed -i '/^snapshot-prefix=/d' "$VLC_RC"
    sed -i '/^osd=/d' "$VLC_RC"
    sed -i '/^video-title-show=/d' "$VLC_RC"
fi

# Generate reference video (30s with visual timing markers)
echo "Generating reference dialogue video..."
VIDEO_FILE="/home/ga/Videos/dialogue_reference.mp4"

ffmpeg -y -f lavfi -i color=c=black:s=1280x720:d=30 -r 30 \
    -vf "drawtext=text='DIALOGUE REFERENCE - Voice Acting Study':fontsize=42:fontcolor=white:x=(w-text_w)/2:y=60:box=1:boxcolor=black@0.7:boxborderw=10,\
         drawtext=text='Time\\: %{pts\\:hms}':fontsize=36:fontcolor=yellow:x=30:y=30:box=1:boxcolor=black@0.7:boxborderw=8,\
         drawtext=text='SETUP LOOP\\: 10.5s to 18.5s':fontsize=32:fontcolor=cyan:x=(w-text_w)/2:y=150:enable='lt(t,8)',\
         drawtext=text='━━━ LOOP START (10.5s) ━━━':fontsize=38:fontcolor=lime:x=(w-text_w)/2:y=(h-text_h)/2-80:enable='between(t,10.3,10.7)',\
         drawtext=text='[Emotional Beat 1]\\nVoice cracks...':fontsize=32:fontcolor=orange:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,10.5,12.5)',\
         drawtext=text='[Emotional Beat 2]\\nTone shifts darker...':fontsize=32:fontcolor=red:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,12.5,15.0)',\
         drawtext=text='[Emotional Beat 3]\\nVoice steadies...':fontsize=32:fontcolor=lightblue:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,15.0,17.5)',\
         drawtext=text='━━━ LOOP END (18.5s) ━━━':fontsize=38:fontcolor=red:x=(w-text_w)/2:y=(h-text_h)/2-80:enable='between(t,18.3,18.7)',\
         drawtext=text='Take snapshots at emotional beats!':fontsize=28:fontcolor=yellow:x=(w-text_w)/2:y=h-80:enable='between(t,10.5,18.5)'" \
    -c:v libx264 -preset fast -pix_fmt yuv420p \
    -f lavfi -i anullsrc=r=44100:cl=stereo -c:a aac -shortest \
    "$VIDEO_FILE" > /tmp/ffmpeg_dialogue.log 2>&1

if [ ! -f "$VIDEO_FILE" ]; then
    echo "ERROR: Failed to generate reference video"
    cat /tmp/ffmpeg_dialogue.log
    exit 1
fi

chown ga:ga "$VIDEO_FILE"
echo "✅ Reference video created: $VIDEO_FILE"

# Launch VLC with RC interface and video
echo "Launching VLC with RC interface..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop --extraintf rc --rc-host localhost:9999 '$VIDEO_FILE' > /tmp/vlc_dialogue_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_dialogue_task.log
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
    sleep 1
done

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Pause video to allow agent to set up loop
echo "Pausing video for setup..."
sleep 2
su - ga -c "DISPLAY=:1 xdotool key space" || true
sleep 0.5

# Seek to just before loop start (10s)
echo "Seeking to 10 seconds..."
su - ga -c "DISPLAY=:1 xdotool key ctrl+Home" || true
sleep 0.5
for i in {1..2}; do
    su - ga -c "DISPLAY=:1 xdotool key shift+Right" || true
    sleep 0.3
done

echo "=== Study Dialogue Delivery Task Setup Complete ==="
echo ""
echo "📝 TASK INSTRUCTIONS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "SCENARIO: You are helping a voice actor study dialogue delivery."
echo "They need to repeatedly watch a specific 8-second segment and"
echo "capture snapshots of key emotional moments."
echo ""
echo "REQUIREMENTS:"
echo ""
echo "1️⃣  SET UP A-B REPEAT LOOP (10.5s to 18.5s):"
echo "    • Enable Advanced Controls: View → Advanced Controls"
echo "    • Seek to 10.5s (use Ctrl+T for 'Go to Time' or Shift+Right to jump)"
echo "    • Click the loop button (or press Shift+L) to set point A"
echo "    • Seek to 18.5s"
echo "    • Click the loop button again (or press Shift+L) to set point B"
echo "    • Video should now loop between these points"
echo ""
echo "2️⃣  ENABLE TIME DISPLAY:"
echo "    • Go to Tools → Preferences → Show Settings: All"
echo "    • Navigate to Video → On-screen display"
echo "    • Enable OSD, or enable 'Show media title on video start'"
echo "    • OR simply ensure time is visible in interface"
echo ""
echo "3️⃣  CONFIGURE SNAPSHOT SETTINGS:"
echo "    • Tools → Preferences → Video"
echo "    • Set 'Video snapshot directory' to: /home/ga/Pictures/voice_acting_reference"
echo "    • Set 'Video snapshot format' to: png"
echo "    • (Optional) Set snapshot prefix to: expression_"
echo ""
echo "4️⃣  TAKE AT LEAST 3 SNAPSHOTS:"
echo "    • Let the loop play"
echo "    • At different emotional beats, press Shift+S to capture"
echo "    • Take snapshots at different moments within the 10.5-18.5s range"
echo ""
echo "5️⃣  VERIFY SETUP:"
echo "    • Let the loop play for at least 3 complete cycles"
echo "    • Ensure snapshots are being saved to the correct directory"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "The video shows timing markers to help you identify the loop points."
echo "Good luck!"