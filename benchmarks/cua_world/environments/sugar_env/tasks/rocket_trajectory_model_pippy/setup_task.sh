#!/bin/bash
echo "=== Setting up physics trajectory task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists with correct permissions
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing files to prevent gaming
rm -f /home/ga/Documents/trajectory_model.py 2>/dev/null || true
rm -f /home/ga/Documents/rocket_trajectory.csv 2>/dev/null || true

# Record task start timestamp for mtime validation
date +%s > /tmp/task_start_ts
chmod 666 /tmp/task_start_ts

# Close any open activities to return to the Sugar home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch the Terminal activity to give the agent a place to work
echo "Launching Terminal activity..."
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.Terminal" &
sleep 8

# Ensure the window is maximized and focused
su - ga -c "$SUGAR_ENV wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz" 2>/dev/null || true

# Take verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/rocket_task_start.png" 2>/dev/null || true

echo "=== physics trajectory task setup complete ==="
echo "Terminal is open. Agent must write a Python script and generate a trajectory CSV."