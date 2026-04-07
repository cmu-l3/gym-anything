#!/bin/bash
echo "=== Setting up HTPC Accessibility & Playback Configuration task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure clean state for VLC config
echo "Resetting VLC configuration to defaults..."
kill_vlc "ga"
rm -rf /home/ga/.config/vlc
mkdir -p /home/ga/.config/vlc
chown -R ga:ga /home/ga/.config

# Create required directories
mkdir -p /home/ga/Videos
mkdir -p /home/ga/Pictures/vlc
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Videos /home/ga/Pictures/vlc /home/ga/Documents

# Generate 4:3 test video with 3 subtitle tracks (Spanish, English, French)
echo "Generating multi-track test video..."
cat > /tmp/esp.srt << 'EOF'
1
00:00:00,000 --> 00:00:30,000
Esta es la pista de subtítulos en español.
EOF

cat > /tmp/eng.srt << 'EOF'
1
00:00:00,000 --> 00:00:30,000
This is the English subtitle track.
It should be displayed in large yellow font.
EOF

cat > /tmp/fra.srt << 'EOF'
1
00:00:00,000 --> 00:00:30,000
Ceci est la piste de sous-titres française.
EOF

# Use FFmpeg to create a 4:3 video (640x480) with audio and 3 embedded subtitles
ffmpeg -y \
    -f lavfi -i "testsrc2=size=640x480:rate=25:duration=30" \
    -f lavfi -i "sine=frequency=440:duration=30" \
    -i /tmp/esp.srt -i /tmp/eng.srt -i /tmp/fra.srt \
    -map 0:v -map 1:a -map 2:s -map 3:s -map 4:s \
    -c:v libx264 -preset ultrafast -b:v 1M \
    -c:a aac -b:a 128k \
    -c:s srt \
    -metadata:s:s:0 language=spa \
    -metadata:s:s:1 language=eng \
    -metadata:s:s:2 language=fra \
    /home/ga/Videos/vintage_film.mkv 2>/dev/null

chown ga:ga /home/ga/Videos/vintage_film.mkv

# Start VLC (empty, to allow the agent to configure it)
su - ga -c "DISPLAY=:1 vlc &"
sleep 3

# Maximize the VLC window
DISPLAY=:1 wmctrl -r "VLC media player" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "VLC media player" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="