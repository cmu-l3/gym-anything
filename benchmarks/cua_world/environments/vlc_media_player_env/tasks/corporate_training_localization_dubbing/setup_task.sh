#!/bin/bash
echo "=== Setting up corporate_training_localization_dubbing task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create required directories
mkdir -p /home/ga/Videos/localized_delivery
mkdir -p /home/ga/Music
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Pictures

# 1. Generate Master Video (45s, 1920x1080, with 440Hz tone representing English audio)
echo "Generating master video..."
ffmpeg -y -f lavfi -i "testsrc2=size=1920x1080:rate=30:duration=45" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=45" \
  -c:v libx264 -preset ultrafast -b:v 2M \
  -c:a aac -b:a 128k \
  /home/ga/Videos/compliance_training_master.mp4 2>/dev/null

# 2. Generate French Dub Track (45s, 880Hz tone representing French audio)
echo "Generating French dub track..."
ffmpeg -y -f lavfi -i "sine=frequency=880:sample_rate=48000:duration=45" \
  -c:a libmp3lame -b:a 128k \
  /home/ga/Music/french_dub_track.mp3 2>/dev/null

# 3. Generate French Subtitles
echo "Generating French subtitles..."
cat > /home/ga/Documents/french_captions.srt << 'SRTEOF'
1
00:00:05,000 --> 00:00:20,000
Bienvenue dans la formation de conformité.

2
00:00:25,000 --> 00:00:40,000
Veuillez respecter les directives de l'entreprise.
SRTEOF

# 4. Generate Watermark Logo (Red square with transparency)
echo "Generating corporate watermark..."
ffmpeg -y -f lavfi -i "color=c=red@0.8:s=200x200" -frames:v 1 /home/ga/Pictures/corp_watermark.png 2>/dev/null

# Set ownership
chown -R ga:ga /home/ga/Videos /home/ga/Music /home/ga/Documents /home/ga/Pictures

# Launch VLC in the background
if ! pgrep -f "vlc" > /dev/null; then
    echo "Starting VLC..."
    su - ga -c "DISPLAY=:1 vlc &"
    sleep 3
fi

# Wait for window to appear and maximize it
for i in {1..10}; do
    if DISPLAY=:1 wmctrl -l | grep -i "VLC media player"; then
        DISPLAY=:1 wmctrl -r "VLC media player" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -a "VLC media player" 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="