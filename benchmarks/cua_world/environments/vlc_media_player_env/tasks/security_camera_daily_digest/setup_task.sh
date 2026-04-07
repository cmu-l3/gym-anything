#!/bin/bash
echo "=== Setting up Security Camera Daily Digest Task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create required directory structure
mkdir -p /home/ga/Videos/security_feeds
mkdir -p /home/ga/Videos/daily_digest/frames
mkdir -p /home/ga/Videos/daily_digest/incidents
mkdir -p /home/ga/Documents

echo "Generating security feed videos (this takes a moment)..."

# Generate Lobby Camera (Blue tint, 180s)
ffmpeg -y -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=180" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=180" \
  -vf "drawtext=text='LOBBY CAM  %{pts\:hms}':x=20:y=20:fontsize=48:fontcolor=white:box=1:boxcolor=black@0.5,drawbox=x=0:y=0:w=1280:h=720:color=blue@0.2:t=fill" \
  -c:v libx264 -preset ultrafast -c:a aac -b:a 128k \
  /home/ga/Videos/security_feeds/camera_lobby.mp4 2>/dev/null

# Generate Parking Camera (Green tint, 180s)
ffmpeg -y -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=180" \
  -f lavfi -i "sine=frequency=500:sample_rate=48000:duration=180" \
  -vf "drawtext=text='PARKING CAM  %{pts\:hms}':x=20:y=20:fontsize=48:fontcolor=white:box=1:boxcolor=black@0.5,drawbox=x=0:y=0:w=1280:h=720:color=green@0.2:t=fill" \
  -c:v libx264 -preset ultrafast -c:a aac -b:a 128k \
  /home/ga/Videos/security_feeds/camera_parking.mp4 2>/dev/null

# Generate Loading Dock Camera (Yellow/Amber tint, 180s)
ffmpeg -y -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=180" \
  -f lavfi -i "sine=frequency=600:sample_rate=48000:duration=180" \
  -vf "drawtext=text='LOADING DOCK  %{pts\:hms}':x=20:y=20:fontsize=48:fontcolor=white:box=1:boxcolor=black@0.5,drawbox=x=0:y=0:w=1280:h=720:color=yellow@0.2:t=fill" \
  -c:v libx264 -preset ultrafast -c:a aac -b:a 128k \
  /home/ga/Videos/security_feeds/camera_loading.mp4 2>/dev/null

echo "Generating guard notes..."
cat > /home/ga/Documents/guard_notes.txt << 'EOF'
=== OVERNIGHT GUARD INCIDENT LOG ===
Date: 2026-03-10
Shift: 22:00 - 06:00
Officer: J. Miller

The following incidents were flagged during the overnight shift for the daily digest review:

1. Camera: Lobby (camera_lobby.mp4)
   Time: 0:30 - 0:50
   Description: Unidentified individual loitering near elevator bank.

2. Camera: Parking (camera_parking.mp4)
   Time: 1:00 - 1:25
   Description: White delivery vehicle sideswipes parked sedan.

3. Camera: Loading Dock (camera_loading.mp4)
   Time: 0:45 - 1:10
   Description: Unauthorized entry attempt at secondary dock door.

4. Camera: Lobby (camera_lobby.mp4)
   Time: 2:00 - 2:20
   Description: Unattended package left at reception desk.

Please ensure all incidents are clipped accurately for the property manager's review.
EOF

# Set permissions
chown -R ga:ga /home/ga/Videos /home/ga/Documents

# Ensure VLC is running to provide the expected initial state
if ! pgrep -f "vlc" > /dev/null; then
    su - ga -c "DISPLAY=:1 vlc /home/ga/Videos/security_feeds &"
    
    # Wait for window
    for i in {1..15}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "VLC"; then
            break
        fi
        sleep 1
    done
fi

# Maximize and focus VLC
DISPLAY=:1 wmctrl -r "VLC" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "VLC" 2>/dev/null || true
sleep 1

# Take initial screenshot for verification evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="