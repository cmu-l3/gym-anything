#!/bin/bash
echo "=== Setting up solar_system_svg_pippy task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing SVG file
rm -f /home/ga/Documents/solar_system.svg 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/solar_system_start_ts
chmod 666 /tmp/solar_system_start_ts

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Verify Sugar is running
if pgrep -f "jarabe.main" > /dev/null 2>&1; then
    echo "Sugar session is running"
else
    echo "WARNING: Sugar session not found, restarting..."
    systemctl restart gdm 2>/dev/null || true
    sleep 15
fi

# Take verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/solar_task_start.png" 2>/dev/null || true

echo "=== solar_system_svg_pippy task setup complete ==="
echo "Sugar desktop is ready. Agent must open Pippy, write the SVG generator, and save it."