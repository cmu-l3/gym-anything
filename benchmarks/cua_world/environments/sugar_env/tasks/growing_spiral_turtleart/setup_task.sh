#!/bin/bash
echo "=== Setting up growing_spiral_turtleart task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing output file to ensure agent creates it fresh
rm -f /home/ga/Documents/growing_spiral.ta 2>/dev/null || true

# Record task start timestamp for anti-gaming (mtime validation)
date +%s > /tmp/growing_spiral_start_ts
chmod 666 /tmp/growing_spiral_start_ts

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch TurtleBlocks with a blank canvas
echo "Launching TurtleArt activity..."
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.TurtleArtActivity" &
sleep 12

# Verify TurtleArt is running
if pgrep -f "TurtleArtActivity" > /dev/null 2>&1; then
    echo "TurtleArt activity is running"
else
    echo "WARNING: TurtleArt activity may not have started"
fi

# Take a verification screenshot of the starting state
su - ga -c "$SUGAR_ENV scrot /tmp/spiral_task_start.png" 2>/dev/null || true

echo "=== growing_spiral_turtleart task setup complete ==="
echo "TurtleBlocks is open with a blank canvas."
echo "Agent must build the spiral logic and save as /home/ga/Documents/growing_spiral.ta"