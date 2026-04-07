#!/bin/bash
echo "=== Setting up Audiobook Chapter Splitting Task ==="

source /workspace/scripts/task_utils.sh || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/Music/audiobook_delivery
mkdir -p /home/ga/Documents

# Generate the raw narration WAV (300 seconds total, stereo, 44.1kHz)
# Using different sine frequencies to simulate different audio segments
# Chapter 1: 0-75s
# Chapter 2: 75-160s (85s)
# Chapter 3: 160-240s (80s)
# Chapter 4: 240-300s (60s)
echo "Generating master audio file..."
ffmpeg -y \
  -f lavfi -i "sine=frequency=440:sample_rate=44100:duration=75" \
  -f lavfi -i "sine=frequency=550:sample_rate=44100:duration=85" \
  -f lavfi -i "sine=frequency=660:sample_rate=44100:duration=80" \
  -f lavfi -i "sine=frequency=770:sample_rate=44100:duration=60" \
  -filter_complex "[0:a][1:a][2:a][3:a]concat=n=4:v=0:a=1[aout]" \
  -map "[aout]" \
  -c:a pcm_s16le -ac 2 -ar 44100 \
  /home/ga/Music/raw_narration.wav 2>/dev/null

# Create chapter markers document
cat > /home/ga/Documents/chapter_markers.txt << 'EOF'
AUDIOBOOK MASTER TIMECODE SHEET
-------------------------------
Book Title: The Art of War
Author: Sun Tzu

Please split the master recording into the following four files.
Encode as 64 kbps Mono MP3 and apply the appropriate ID3 tags (Artist, Album, Title, Track):

Chapter 1: Laying Plans
Start: 00:00
End: 01:15

Chapter 2: Waging War
Start: 01:15
End: 02:40

Chapter 3: Attack by Stratagem
Start: 02:40
End: 04:00

Chapter 4: Tactical Dispositions
Start: 04:00
End: 05:00
EOF

# Ensure permissions
chown -R ga:ga /home/ga/Music /home/ga/Documents

# Launch VLC in the background to set the initial state
if ! pgrep -f "vlc" > /dev/null; then
    echo "Starting VLC..."
    su - ga -c "DISPLAY=:1 vlc --no-video-title-show &"
    sleep 3
fi

# Maximize window
DISPLAY=:1 wmctrl -r "VLC media player" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "VLC media player" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="