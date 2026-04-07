#!/bin/bash
# Do NOT use set -e
echo "=== Setting up turtleart_seattle_rainfall task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing file to prevent gaming
rm -f /home/ga/Documents/seattle_rainfall.ta 2>/dev/null || true

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Record task start timestamp for mtime validation
date +%s > /tmp/seattle_rainfall_start_ts
chmod 666 /tmp/seattle_rainfall_start_ts

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

# Take a verification screenshot of the initial state
su - ga -c "$SUGAR_ENV scrot /tmp/rainfall_task_start.png" 2>/dev/null || true

echo "=== turtleart_seattle_rainfall task setup complete ==="
echo "TurtleBlocks is open with a blank canvas."
echo "Agent must build a bar chart program and save it to /home/ga/Documents/seattle_rainfall.ta"