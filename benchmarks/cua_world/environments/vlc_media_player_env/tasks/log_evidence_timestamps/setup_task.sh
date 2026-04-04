#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Log Evidence Timestamps Task ==="

kill_vlc ga
sleep 1

# Create output directories
mkdir -p /home/ga/Pictures/evidence
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Pictures/evidence
chown ga:ga /home/ga/Documents

# Generate evidence footage with distinct visual events at known timestamps
DURATION=38
VIDEO_OUT="/home/ga/Videos/evidence_footage.mp4"

echo "Generating evidence footage with timed events..."

# Create video with visual markers at specific timestamps using ffmpeg
# Events at: 5s, 12s, 18s, 25s, 32s
ffmpeg -y -f lavfi -i color=c=gray:s=1280x720:d=$DURATION:r=30 \
    -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='EVIDENCE FOOTAGE':fontsize=36:fontcolor=white:x=(w-text_w)/2:y=40:box=1:boxcolor=black@0.5:boxborderw=5,\
         drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='🚗 RED VEHICLE ENTERS':fontsize=70:fontcolor=red:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,5,8)',\
         drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='🚙 BLUE VEHICLE ENTERS':fontsize=70:fontcolor=blue:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,12,15)',\
         drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='💥 COLLISION OCCURS':fontsize=80:fontcolor=yellow:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,18,21)',\
         drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='🚑 EMERGENCY ARRIVES':fontsize=70:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,25,28)',\
         drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='👤 PEOPLE EXIT VEHICLES':fontsize=65:fontcolor=lightgreen:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,32,35)',\
         drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='TIME\: %{pts\:hms}':fontsize=28:fontcolor=yellow:x=20:y=h-50:box=1:boxcolor=black@0.7:boxborderw=3" \
    -c:v libx264 -pix_fmt yuv420p -preset fast "$VIDEO_OUT" \
    > /tmp/ffmpeg_evidence.log 2>&1

if [ ! -f "$VIDEO_OUT" ]; then
    echo "ERROR: Failed to generate evidence footage"
    cat /tmp/ffmpeg_evidence.log
    exit 1
fi

echo "✅ Generated evidence footage: $VIDEO_OUT"
ls -lh "$VIDEO_OUT"

# Create event checklist for the user
cat > /home/ga/Documents/events_to_log.txt << 'EOF'
EVIDENCE REVIEW TASK
====================

Video File: /home/ga/Videos/evidence_footage.mp4

Your task is to review the evidence footage and create a timestamp log 
documenting when the following events occur:

1. Red vehicle enters the frame
2. Blue vehicle enters the frame
3. Collision/incident occurs
4. Emergency vehicle arrives
5. People exit vehicles

Instructions:
-------------
1. Open the video in VLC (it should auto-play)
2. Watch carefully and note when each event occurs
3. Create a log file at: /home/ga/Documents/evidence_log.txt

Log Format:
-----------
Use timestamps in MM:SS or HH:MM:SS format, followed by event description.
Ensure events are listed in chronological order.

Example format:
  00:05 - Red vehicle enters frame from left
  00:12 - Blue vehicle enters frame from right
  00:18 - Collision occurs at center
  (etc.)

OPTIONAL BONUS:
--------------
Capture snapshots of each event and save to: /home/ga/Pictures/evidence/
Use Shift+S to take snapshots in VLC.

Good luck!
EOF

chown ga:ga /home/ga/Documents/events_to_log.txt
chown ga:ga "$VIDEO_OUT"

echo "✅ Created event checklist: /home/ga/Documents/events_to_log.txt"

# Launch VLC with the evidence footage
echo "Launching VLC with evidence footage..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop /home/ga/Videos/evidence_footage.mp4 > /tmp/vlc_evidence_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_evidence_task.log
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

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Pause the video so agent can start fresh
echo "Pausing video at start..."
sleep 2
su - ga -c "DISPLAY=:1 xdotool key space" || true
sleep 0.5

echo "=== Log Evidence Timestamps Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Read the checklist: /home/ga/Documents/events_to_log.txt"
echo "  2. Watch the video: /home/ga/Videos/evidence_footage.mp4"
echo "  3. Note timestamps when each event occurs"
echo "  4. Create log file: /home/ga/Documents/evidence_log.txt"
echo "  5. Format: MM:SS - Event description"
echo "  6. BONUS: Capture snapshots to /home/ga/Pictures/evidence/"
echo ""
echo "Use Space to play/pause, Shift+Right/Left to seek"