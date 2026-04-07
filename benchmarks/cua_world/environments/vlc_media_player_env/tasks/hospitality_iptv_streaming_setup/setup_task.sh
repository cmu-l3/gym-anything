#!/bin/bash
echo "=== Setting up Hospitality IPTV Streaming Setup task ==="

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure clean state
pkill -f vlc || true
rm -f /home/ga/Documents/start_promo.sh 2>/dev/null || true
rm -f /home/ga/Documents/start_ambient.sh 2>/dev/null || true

mkdir -p /home/ga/Videos
mkdir -p /home/ga/Music
mkdir -p /home/ga/Documents

# Download master media (official Blender foundation sample)
echo "Downloading master promo video..."
if ! wget -q -T 60 -O /home/ga/Videos/resort_promo_master.mp4 "https://download.blender.org/peach/trailer/trailer_1080p.mov"; then
    echo "Warning: Failed to download real video, falling back to generated testsrc..."
    ffmpeg -y -f lavfi -i testsrc2=size=1920x1080:rate=30:duration=30 -c:v libx264 -preset ultrafast -b:v 5M /home/ga/Videos/resort_promo_master.mp4 2>/dev/null
fi

echo "Extracting ambient audio..."
ffmpeg -y -i /home/ga/Videos/resort_promo_master.mp4 -vn -c:a pcm_s16le -ar 44100 -ac 2 /home/ga/Music/lobby_ambient.wav 2>/dev/null || true

# Check if audio was successfully extracted, if not, create a fallback
if [ ! -s /home/ga/Music/lobby_ambient.wav ]; then
    echo "Warning: Audio extraction failed, generating fallback audio..."
    ffmpeg -y -f lavfi -i "sine=frequency=440:duration=30" -c:a pcm_s16le /home/ga/Music/lobby_ambient.wav 2>/dev/null
fi

# Set ownership so the user can manipulate them
chown -R ga:ga /home/ga/Videos /home/ga/Music /home/ga/Documents

# Create a spec file for the agent to reference easily
cat > /home/ga/Documents/streaming_specs.txt << 'EOF'
=== HOSPITALITY IPTV STREAMING SPECS ===

Channel 1: Resort Promo Video
- Source: /home/ga/Videos/resort_promo_master.mp4
- Output Port: 8080
- Output Path: /promo
- Protocol: HTTP
- Multiplexer: MPEG-TS (ts)
- Video Transcoding: H.264 (h264), 1280x720 resolution, ~2000 kbps
- Audio Transcoding: AAC or MP3 (agent choice), ~128 kbps
- Playback: Must loop indefinitely

Channel 2: Lobby Ambient Audio
- Source: /home/ga/Music/lobby_ambient.wav
- Output Port: 8081
- Output Path: /ambient
- Protocol: HTTP
- Multiplexer: RAW or TS
- Video Transcoding: None
- Audio Transcoding: MP3 (mp3), ~192 kbps
- Playback: Must loop indefinitely

Task:
1. Launch both streams in the background.
2. Save the exact VLC CLI commands you used to:
   - /home/ga/Documents/start_promo.sh
   - /home/ga/Documents/start_ambient.sh
EOF

chown ga:ga /home/ga/Documents/streaming_specs.txt

# Take initial screenshot of the clean desktop
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="