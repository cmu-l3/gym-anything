#!/bin/bash
echo "=== Setting up muybridge_stop_motion_html task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/muybridge_task_start_ts
chmod 666 /tmp/muybridge_task_start_ts

# Prepare directory
mkdir -p /home/ga/Documents/muybridge
rm -f /home/ga/Documents/muybridge/*
rm -f /home/ga/Documents/horse_motion.gif
rm -f /home/ga/Documents/cinema_history.html

# Download authentic Muybridge sequence from Wikimedia Commons
echo "Downloading Muybridge sequence..."
wget -q -O /tmp/muybridge.gif "https://upload.wikimedia.org/wikipedia/commons/d/dd/Muybridge_race_horse_animated.gif"

# Split into individual raw frames using ImageMagick
if [ -f /tmp/muybridge.gif ]; then
    convert /tmp/muybridge.gif -coalesce /home/ga/Documents/muybridge/frame_%02d.jpg
    rm -f /tmp/muybridge.gif
else
    # Fallback if download fails (to prevent task breakage)
    echo "Download failed, generating fallback authentic-style frames..."
    for i in {0..10}; do
        convert -size 400x300 xc:white -fill black -pointsize 24 -gravity center -draw "text 0,0 'Muybridge Frame $i\n1878'" /home/ga/Documents/muybridge/frame_$(printf "%02d" $i).jpg
    done
fi

chown -R ga:ga /home/ga/Documents/muybridge

# Ensure Sugar home view is visible
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3
if ! pgrep -f "jarabe.main" > /dev/null 2>&1; then
    systemctl restart gdm 2>/dev/null || true
    sleep 15
fi

# Launch the Terminal activity for the agent to start working
echo "Launching Terminal activity..."
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.Terminal" &
sleep 5

# Maximize Terminal
WID=$(DISPLAY=:1 wmctrl -l | grep -i "Terminal" | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/muybridge_task_start.png" 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Raw frames are in /home/ga/Documents/muybridge/"