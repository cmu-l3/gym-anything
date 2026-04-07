#!/bin/bash
echo "=== Setting up wikipedia_illustrated_factsheet_write task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing files to ensure a clean state
rm -f /home/ga/Documents/capybara*.jpg 2>/dev/null || true
rm -f /home/ga/Documents/capybara*.odt 2>/dev/null || true

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/factsheet_task_start_ts
chmod 666 /tmp/factsheet_task_start_ts

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Take initial verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/factsheet_task_start.png" 2>/dev/null || true

echo "=== setup complete ==="