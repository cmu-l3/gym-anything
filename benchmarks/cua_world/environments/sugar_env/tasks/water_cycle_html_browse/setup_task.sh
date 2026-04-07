#!/bin/bash
echo "=== Setting up water_cycle_html_browse task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists with correct ownership
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing files to ensure the agent creates them fresh
rm -f /home/ga/Documents/water_cycle.html 2>/dev/null || true
rm -f /home/ga/Documents/water_cycle_summary.txt 2>/dev/null || true

# Record task start timestamp (crucial for anti-gaming)
date +%s > /tmp/water_cycle_start_ts
chmod 666 /tmp/water_cycle_start_ts

# Close any open activities to start from a clean home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Verify Sugar session is running
if ! pgrep -f "jarabe.main" > /dev/null 2>&1; then
    echo "Sugar session not found, attempting to restart..."
    systemctl restart gdm 2>/dev/null || true
    sleep 15
fi

# Take verification screenshot of the clean starting state
su - ga -c "$SUGAR_ENV scrot /tmp/water_cycle_start.png" 2>/dev/null || true

echo "=== water_cycle_html_browse task setup complete ==="
echo "Agent must create water_cycle.html and water_cycle_summary.txt in /home/ga/Documents/"
echo "and then open the HTML file in the Sugar Browse activity."