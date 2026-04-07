#!/bin/bash
echo "=== Setting up multilang_subtitle_mkv_packaging task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/Videos/release
mkdir -p /home/ga/Documents/subs

# Generate source video (30 seconds, H.264 video, AAC stereo audio)
echo "Generating source video..."
ffmpeg -y -f lavfi -i "testsrc2=size=1280x720:rate=24:duration=30" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=30" \
  -c:v libx264 -preset ultrafast -b:v 2M \
  -c:a aac -b:a 128k \
  /home/ga/Videos/documentary_final.mp4 2>/dev/null

# Generate SRT files with baseline timestamps
echo "Generating original subtitle files..."

cat > /home/ga/Documents/subs/en_original.srt << 'EOF'
1
00:00:02,000 --> 00:00:05,000
Welcome to the documentary.

2
00:00:10,000 --> 00:00:15,000
This is a test of subtitle timing.
EOF

cat > /home/ga/Documents/subs/es_original.srt << 'EOF'
1
00:00:02,000 --> 00:00:05,000
Bienvenidos al documental.

2
00:00:10,000 --> 00:00:15,000
Esta es una prueba de sincronización.
EOF

cat > /home/ga/Documents/subs/fr_original.srt << 'EOF'
1
00:00:02,000 --> 00:00:05,000
Bienvenue dans le documentaire.

2
00:00:10,000 --> 00:00:15,000
Ceci est un test de synchronisation.
EOF

# Set appropriate permissions
chown -R ga:ga /home/ga/Videos
chown -R ga:ga /home/ga/Documents

# Launch VLC to establish correct application focus state
echo "Launching VLC Media Player..."
su - ga -c "DISPLAY=:1 vlc &" 2>/dev/null || true

# Wait for VLC to be visible
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "VLC media player"; then
        break
    fi
    sleep 0.5
done

# Maximize and focus VLC
DISPLAY=:1 wmctrl -r "VLC media player" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "VLC media player" 2>/dev/null || true

# Give UI time to stabilize
sleep 1

# Capture initial screenshot as evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="