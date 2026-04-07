#!/bin/bash
echo "=== Setting up Retro FMV Downgrade Pipeline Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

kill_vlc ga

# Create necessary directories
mkdir -p /home/ga/Videos/raw_footage
mkdir -p /home/ga/Videos/retro_assets
mkdir -p /home/ga/Documents/scripts

echo "Generating raw modern 1080p footage..."
# We use testsrc2 (complex colored pattern with moving elements) to simulate HD video
# Scene 1: Intro
ffmpeg -y -f lavfi -i "testsrc2=size=1920x1080:rate=60:duration=15" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=15" \
  -c:v libx264 -preset ultrafast -b:v 4M \
  -c:a aac -b:a 192k -ac 2 -ar 48000 \
  /home/ga/Videos/raw_footage/scene1_intro.mp4 2>/dev/null

# Scene 2: Action
ffmpeg -y -f lavfi -i "testsrc2=size=1920x1080:rate=60:duration=15" \
  -f lavfi -i "sine=frequency=880:sample_rate=48000:duration=15" \
  -vf "hue=H=PI/2" \
  -c:v libx264 -preset ultrafast -b:v 4M \
  -c:a aac -b:a 192k -ac 2 -ar 48000 \
  /home/ga/Videos/raw_footage/scene2_action.mp4 2>/dev/null

# Scene 3: Ending
ffmpeg -y -f lavfi -i "testsrc2=size=1920x1080:rate=60:duration=15" \
  -f lavfi -i "sine=frequency=523:sample_rate=44100:duration=15" \
  -vf "hue=H=PI" \
  -c:v libx264 -preset ultrafast -b:v 4M \
  -c:a aac -b:a 192k -ac 2 -ar 44100 \
  /home/ga/Videos/raw_footage/scene3_ending.mp4 2>/dev/null

echo "Generating subtitle scripts..."
cat > /home/ga/Documents/scripts/scene1.srt << 'SRTEOF'
1
00:00:02,000 --> 00:00:05,000
Commander, the alien forces are approaching!

2
00:00:06,000 --> 00:00:10,000
We must initialize the defense grid immediately.
SRTEOF

cat > /home/ga/Documents/scripts/scene2.srt << 'SRTEOF'
1
00:00:03,000 --> 00:00:07,000
Warning! Hull breach detected in sector 7.

2
00:00:08,000 --> 00:00:12,000
Rerouting auxiliary power to shields!
SRTEOF

cat > /home/ga/Documents/scripts/scene3.srt << 'SRTEOF'
1
00:00:01,000 --> 00:00:06,000
The core is destabilizing! Get to the escape pods!

2
00:00:08,000 --> 00:00:13,000
It was an honor serving with you, Captain.
SRTEOF

# Ensure permissions
chown -R ga:ga /home/ga/Videos
chown -R ga:ga /home/ga/Documents

# Pre-launch a terminal for the user to work in
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/Videos/raw_footage &" 2>/dev/null || true
sleep 3

# Take initial screenshot showing starting state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="