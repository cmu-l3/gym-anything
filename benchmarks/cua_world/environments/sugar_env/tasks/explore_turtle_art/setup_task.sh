#!/bin/bash
echo "=== Setting up explore_turtle_art task ==="

# Ensure the TurtleArt program files are available
if [ ! -f /home/ga/Documents/turtleart/spiral.ta ]; then
    echo "TurtleArt files not found, copying from data..."
    mkdir -p /home/ga/Documents/turtleart
    cp /workspace/data/turtleart/*.ta /home/ga/Documents/turtleart/ 2>/dev/null || true
    chown -R ga:ga /home/ga/Documents/turtleart
fi

# Sugar runs as the GDM session on :1.
# sugar-launch requires the user's DBUS session bus.
SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Close any open activity first to return to home view.
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch the TurtleArt activity programmatically via DBUS
echo "Launching TurtleArt activity..."
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.TurtleArtActivity" &
sleep 10

# Verify TurtleArt activity is running
if pgrep -f "TurtleArtActivity" > /dev/null 2>&1; then
    echo "TurtleArt activity is running"
else
    echo "WARNING: TurtleArt activity may not have started"
fi

# Take a verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/task_start_state.png" 2>/dev/null || true

echo "=== explore_turtle_art task setup complete ==="
echo "TurtleArt activity should be open with blank canvas"
echo "The spiral.ta program file is at /home/ga/Documents/turtleart/spiral.ta"
echo "Agent should load the spiral program and run it"
