#!/bin/bash
# Setup script for ktv_backing_track_pipeline task
set -e

echo "=== Setting up KTV Backing Track Pipeline ==="

# Record start time
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/Videos/ktv_inbox
mkdir -p /home/ga/Videos/ktv_ready
mkdir -p /home/ga/Pictures

# Generate venue watermark logo (transparent PNG)
# Using a fully transparent background with white text
ffmpeg -y -f lavfi -i color=c=black@0.0:s=250x100,format=rgba \
  -vf "drawtext=text='STAR KTV':fontsize=48:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2" \
  -frames:v 1 /home/ga/Pictures/ktv_logo.png 2>/dev/null

# Track 1 frequencies: Center=1000Hz (vocals), L=400Hz, R=800Hz (instruments)
echo "Generating Track 1..."
ffmpeg -y -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=15" \
  -f lavfi -i "aevalsrc='0.5*sin(2*PI*400*t) + 0.5*sin(2*PI*1000*t)|0.5*sin(2*PI*800*t) + 0.5*sin(2*PI*1000*t)':d=15:s=44100" \
  -vf "drawtext=text='Track 1 - Original Master':fontsize=36:fontcolor=white:x=20:y=20:box=1:boxcolor=black@0.5" \
  -c:v libx264 -preset ultrafast -b:v 2M \
  -c:a aac -b:a 192k \
  /home/ga/Videos/ktv_inbox/track1_original.mp4 2>/dev/null

cat > /home/ga/Videos/ktv_inbox/track1.srt << 'EOF'
1
00:00:01,000 --> 00:00:10,000
♪ This is the first song lyric ♪

2
00:00:10,500 --> 00:00:14,000
♪ Singing along to track one ♪
EOF

# Track 2 frequencies: Center=1500Hz, L=500Hz, R=900Hz
echo "Generating Track 2..."
ffmpeg -y -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=15" \
  -f lavfi -i "aevalsrc='0.5*sin(2*PI*500*t) + 0.5*sin(2*PI*1500*t)|0.5*sin(2*PI*900*t) + 0.5*sin(2*PI*1500*t)':d=15:s=44100" \
  -vf "drawtext=text='Track 2 - Original Master':fontsize=36:fontcolor=white:x=20:y=20:box=1:boxcolor=black@0.5" \
  -c:v libx264 -preset ultrafast -b:v 2M \
  -c:a aac -b:a 192k \
  /home/ga/Videos/ktv_inbox/track2_original.mp4 2>/dev/null

cat > /home/ga/Videos/ktv_inbox/track2.srt << 'EOF'
1
00:00:01,000 --> 00:00:10,000
♪ Second verse, same as the first ♪

2
00:00:10,500 --> 00:00:14,000
♪ Welcome to Star KTV ♪
EOF

# Track 3 frequencies: Center=1200Hz, L=300Hz, R=700Hz
echo "Generating Track 3..."
ffmpeg -y -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=15" \
  -f lavfi -i "aevalsrc='0.5*sin(2*PI*300*t) + 0.5*sin(2*PI*1200*t)|0.5*sin(2*PI*700*t) + 0.5*sin(2*PI*1200*t)':d=15:s=44100" \
  -vf "drawtext=text='Track 3 - Original Master':fontsize=36:fontcolor=white:x=20:y=20:box=1:boxcolor=black@0.5" \
  -c:v libx264 -preset ultrafast -b:v 2M \
  -c:a aac -b:a 192k \
  /home/ga/Videos/ktv_inbox/track3_original.mp4 2>/dev/null

cat > /home/ga/Videos/ktv_inbox/track3.srt << 'EOF'
1
00:00:01,000 --> 00:00:10,000
♪ The final track is here ♪

2
00:00:10,500 --> 00:00:14,000
♪ Sing your heart out! ♪
EOF

# Fix permissions
chown -R ga:ga /home/ga/Videos /home/ga/Pictures

# Ensure VLC is not running
pkill -f vlc || true

# Take an initial screenshot (desktop should be visible)
sleep 2
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="