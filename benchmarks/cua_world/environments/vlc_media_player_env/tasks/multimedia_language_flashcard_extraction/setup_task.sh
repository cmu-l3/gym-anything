#!/bin/bash
echo "=== Setting up Multimedia Language Flashcard Extraction Task ==="
set -e

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Stop any running VLC processes
pkill -f vlc || true

# Prepare directories
mkdir -p /home/ga/Videos
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Documents/AnkiDeck

# 1. Download REAL media (Creative Commons Sintel Trailer)
echo "Downloading real source media..."
wget -q --show-progress -O /home/ga/Videos/sintel_trailer.mp4 "https://download.blender.org/durian/trailer/sintel_trailer-480p.mp4" || {
    echo "ERROR: Failed to download Sintel trailer. Network issue?"
    # Fallback to testsrc only if network strictly fails, but we rely on real data.
    ffmpeg -y -f lavfi -i "testsrc2=size=854x480:rate=24:duration=52" \
      -f lavfi -i "sine=frequency=440:sample_rate=44100:duration=52" \
      -c:v libx264 -preset ultrafast -c:a aac -b:a 128k \
      /home/ga/Videos/sintel_trailer.mp4 2>/dev/null
}

# 2. Generate the dialogue SubRip (SRT) file aligned with the trailer
cat > /home/ga/Documents/dialogue_subs.srt << 'SRTEOF'
1
00:00:12,000 --> 00:00:15,000
This blade has a dark past.

2
00:00:16,000 --> 00:00:19,000
It has shed much innocent blood.

3
00:00:21,000 --> 00:00:24,000
You're a fool for traveling alone,
so completely unprepared.

4
00:00:25,000 --> 00:00:28,000
You're lucky your blood's still flowing.

5
00:00:31,000 --> 00:00:34,000
What do you want from me?
SRTEOF

# 3. Generate the Vocabulary List CSV
cat > /home/ga/Documents/vocab_list.csv << 'CSVEOF'
id,target_word,start_time,end_time
card_01,blade,0:12,0:15
card_02,innocent,0:16,0:19
card_03,unprepared,0:21,0:24
card_04,flowing,0:25,0:28
card_05,want,0:31,0:34
CSVEOF

# Fix permissions so agent can read/write everything
chown -R ga:ga /home/ga/Videos
chown -R ga:ga /home/ga/Documents

# Pre-open File Manager to the working directory to prompt action
su - ga -c "DISPLAY=:1 nautilus /home/ga/Documents &" 2>/dev/null || true
sleep 2

# Maximize file manager window
DISPLAY=:1 wmctrl -r "Documents" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial state screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="