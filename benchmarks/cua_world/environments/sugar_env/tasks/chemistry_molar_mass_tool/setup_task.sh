#!/bin/bash
echo "=== Setting up chemistry_molar_mass_tool task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Record task start timestamp for mtime validation
date +%s > /tmp/molar_mass_task_start_ts
chmod 666 /tmp/molar_mass_task_start_ts

# Ensure Documents directory exists and clean previous artifacts
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/molar_mass.py
rm -f /home/ga/Documents/results.txt
chown ga:ga /home/ga/Documents

# Close any open activities to return to the Sugar home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch the Sugar Terminal activity for the agent to use
echo "Launching Terminal activity..."
su - ga -c "$SUGAR_ENV sugar-launch sugar-terminal-activity" &
sleep 5

# Verify Terminal is running
if pgrep -f "TerminalActivity" > /dev/null 2>&1; then
    echo "Terminal activity is running"
else
    echo "WARNING: Terminal activity may not have started"
fi

# Take a verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== chemistry_molar_mass_tool task setup complete ==="