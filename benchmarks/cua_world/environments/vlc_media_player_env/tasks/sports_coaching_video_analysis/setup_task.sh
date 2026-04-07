#!/bin/bash
echo "=== Setting up Sports Coaching Video Analysis task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/Videos
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Pictures/vlc

# Ensure no existing files from previous runs
rm -rf /home/ga/Videos/game_analysis 2>/dev/null || true
rm -f /home/ga/Videos/game_footage.mp4 2>/dev/null || true

# Generate the 180-second game footage
# - Video: 1280x720 test pattern with burned-in timecode for exact timestamping
# - Audio: Left channel = 330Hz sine tone (simulating coach lapel mic)
# - Audio: Right channel = White noise (simulating crowd ambience)
echo "Generating game footage (this will take a moment)..."
su - ga -c "ffmpeg -y -f lavfi -i 'testsrc2=size=1280x720:rate=30:duration=180' \
  -f lavfi -i 'sine=frequency=330:sample_rate=44100:duration=180' \
  -f lavfi -i 'anoisesrc=c=white:sample_rate=44100:duration=180' \
  -filter_complex '[1:a][2:a]join=inputs=2:channel_layout=stereo[aout];[0:v]drawtext=text=\"MATCH CLOCK %{pts\\\\:hms}\":x=(w-tw)/2:y=50:fontsize=64:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=8[vout]' \
  -map '[vout]' -map '[aout]' \
  -c:v libx264 -preset ultrafast -crf 23 \
  -c:a aac -b:a 128k \
  /home/ga/Videos/game_footage.mp4 > /dev/null 2>&1"

# Generate the game log
cat > /home/ga/Documents/game_log.txt << 'LOGEOF'
=== MATCH TACTICAL LOG ===
Date: Saturday, March 7th
Opponent: Metro City FC
Camera: Coach tactical cam (Audio L = Coach Mic, Audio R = Crowd)

Key Plays for Review Session:
---------------------------------------------------------
Play 1: Counter Attack       | Start: 0:10 | End: 0:30
Play 2: Defensive Set Piece  | Start: 0:40 | End: 1:05
Play 3: Through Ball         | Start: 1:15 | End: 1:35
Play 4: Pressing Trap        | Start: 1:45 | End: 2:10
Play 5: Wing Overlap         | Start: 2:20 | End: 2:40
Play 6: Goal Kick Buildup    | Start: 2:45 | End: 3:00
---------------------------------------------------------

Reminder for Monday's Session:
- Cut the 6 plays exactly as timestamped.
- Need half-speed slow-mo replays for plays 2, 4, and 6.
- Grab formation snapshots at the exact start of all 6 plays.
- Isolate my commentary (Left Channel only!) to a mono MP3.
- Make an M3U playlist of plays 1, 3, and 5.
- Package everything in /home/ga/Videos/game_analysis/ and document with a JSON manifest.
LOGEOF

chown ga:ga /home/ga/Documents/game_log.txt

# Start VLC
if ! pgrep -f "vlc" > /dev/null; then
    echo "Starting VLC..."
    su - ga -c "DISPLAY=:1 vlc --no-video-title-show /home/ga/Videos/game_footage.mp4 &"
    sleep 3
fi

# Wait for window to appear and maximize it
for i in {1..15}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "vlc"; then
        DISPLAY=:1 wmctrl -r "VLC" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -a "VLC" 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot for evidence
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="