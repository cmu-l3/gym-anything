#!/bin/bash
echo "=== Setting up playtest_ux_analysis_pipeline task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create directories
mkdir -p /home/ga/Videos
mkdir -p /home/ga/Documents/ux_report

# Clean up any existing files
rm -f /home/ga/Videos/playtest_session_04.mkv 2>/dev/null

# Create dual-audio MKV file with visually changing timestamps
echo "Generating playtest recording..."
ffmpeg -y -f lavfi -i "testsrc2=size=1920x1080:rate=30:duration=120" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=120" \
  -f lavfi -i "sine=frequency=880:sample_rate=44100:duration=120" \
  -filter_complex "[0:v]drawtext=text='Playtest Time \: %{pts\:hms}':fontsize=72:fontcolor=white:box=1:boxcolor=black@0.5:x=50:y=50[v]" \
  -map "[v]" -map 1:a -map 2:a \
  -c:v libx264 -preset ultrafast -b:v 2M \
  -c:a:0 aac -b:a:0 192k -ac:a:0 2 \
  -c:a:1 libmp3lame -b:a:1 128k -ac:a:1 1 \
  -metadata:s:a:0 title="Game Audio" \
  -metadata:s:a:1 title="Player Mic" \
  /home/ga/Videos/playtest_session_04.mkv 2>/dev/null

# Ensure proper ownership
chown -R ga:ga /home/ga/Videos/playtest_session_04.mkv
chown -R ga:ga /home/ga/Documents/ux_report

# Start VLC but don't play yet
if ! pgrep -f "vlc" > /dev/null; then
    su - ga -c "DISPLAY=:1 vlc --no-video-title-show &" 2>/dev/null || true
    sleep 3
fi

# Maximize VLC window
DISPLAY=:1 wmctrl -r "VLC media player" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "VLC media player" 2>/dev/null || true

# Take screenshot of initial state
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="