#!/bin/bash
# Do NOT use set -e
echo "=== Setting up gapminder_demographics_worksheet task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists with correct permissions
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing files to prevent gaming
rm -f /home/ga/Documents/demographics_worksheet.odt 2>/dev/null || true
rm -f /home/ga/Documents/gapminder.json 2>/dev/null || true

# Record task start timestamp for mtime validation
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# Close any open activities first to return to the home view cleanly
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Ensure Sugar home view is running
if ! pgrep -f "jarabe.main" > /dev/null 2>&1; then
    echo "Sugar session not found, attempting to restart GDM..."
    systemctl restart gdm 2>/dev/null || true
    sleep 15
fi

# Take a verification screenshot of initial state
su - ga -c "$SUGAR_ENV scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== gapminder_demographics_worksheet task setup complete ==="
echo "Sugar home view is ready. Agent must use Terminal to download the Gapminder JSON,"
echo "extract data, and use Write to create an ODT worksheet."