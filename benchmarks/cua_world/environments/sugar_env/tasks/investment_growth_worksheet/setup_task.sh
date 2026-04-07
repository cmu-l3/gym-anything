#!/bin/bash
echo "=== Setting up investment_growth_worksheet task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing file to prevent gaming
rm -f /home/ga/Documents/investment_growth.odt 2>/dev/null || true

# Record task start timestamp for mtime validation
date +%s > /tmp/investment_task_start_ts
chmod 666 /tmp/investment_task_start_ts

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Ensure Sugar home view is running (restart session if needed)
if ! pgrep -f "jarabe.main" > /dev/null 2>&1; then
    echo "Sugar session not found, attempting to restart..."
    systemctl restart gdm 2>/dev/null || true
    sleep 15
fi

# Take verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/investment_task_start.png" 2>/dev/null || true

echo "=== investment_growth_worksheet task setup complete ==="
echo "Sugar home view is ready. Agent must open Write and create the economics worksheet."