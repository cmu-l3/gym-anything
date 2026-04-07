#!/bin/bash
# Do NOT use set -e
echo "=== Setting up calculate_physics_problems task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing file
rm -f /home/ga/Documents/physics_answers.txt 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/physics_answers_start_ts
chmod 666 /tmp/physics_answers_start_ts

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Ensure Sugar home view is showing
if ! pgrep -f "jarabe.main" > /dev/null 2>&1; then
    echo "Sugar session not found, attempting to restart..."
    systemctl restart gdm 2>/dev/null || true
    sleep 15
fi

# Take verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/physics_task_start.png" 2>/dev/null || true

echo "=== calculate_physics_problems task setup complete ==="