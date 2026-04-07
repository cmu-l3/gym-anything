#!/bin/bash
echo "=== Setting up dihybrid_punnett_generator task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove existing files to ensure agent starts fresh
rm -f /home/ga/Documents/punnett_generator.py 2>/dev/null || true
rm -f /home/ga/Documents/punnett_square.html 2>/dev/null || true

# Record task start timestamp for mtime validation
date +%s > /tmp/punnett_start_ts
chmod 666 /tmp/punnett_start_ts

# Close any open activity to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch Terminal activity
echo "Launching Terminal activity..."
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.Terminal" &
sleep 5

# Take initial screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/punnett_task_start.png" 2>/dev/null || true

echo "=== Task setup complete ==="