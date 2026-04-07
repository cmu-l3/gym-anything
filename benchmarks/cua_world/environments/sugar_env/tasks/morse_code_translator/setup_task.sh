#!/bin/bash
echo "=== Setting up morse_code_translator task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure clean start state
mkdir -p /home/ga/Documents
rm -rf /home/ga/Documents/morse
chown ga:ga /home/ga/Documents

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# Close any open activities to return to the Sugar home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch the Sugar Terminal Activity
echo "Launching Terminal activity..."
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.Terminal" &
sleep 5

# Ensure the window is fully loaded and focused
if pgrep -f "terminal\|Terminal" > /dev/null 2>&1; then
    echo "Terminal activity is running."
else
    echo "WARNING: Terminal activity may not have started."
fi

# Take an initial screenshot for verification evidence
su - ga -c "$SUGAR_ENV scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Setup complete ==="
echo "Terminal is open. Agent must create the translation system in /home/ga/Documents/morse/"