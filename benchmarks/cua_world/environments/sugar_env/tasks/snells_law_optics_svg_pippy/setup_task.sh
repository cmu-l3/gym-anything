#!/bin/bash
echo "=== Setting up snells_law_optics_svg_pippy task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists and has correct ownership
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing files to ensure the agent creates them fresh
rm -f /home/ga/Documents/snells_law.py 2>/dev/null || true
rm -f /home/ga/Documents/refraction.svg 2>/dev/null || true

# Record task start timestamp for mtime validation (anti-gaming)
date +%s > /tmp/snells_law_start_ts
chmod 666 /tmp/snells_law_start_ts

# Close any open activity first to return to the home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Verify Sugar desktop is running
if ! pgrep -f "jarabe.main" > /dev/null 2>&1; then
    echo "Sugar session not found, attempting to restart..."
    systemctl restart gdm 2>/dev/null || true
    sleep 15
fi

# Take an initial verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/snells_law_start.png" 2>/dev/null || true

echo "=== snells_law_optics_svg_pippy task setup complete ==="
echo "Sugar home view ready."
echo "Agent must create snells_law.py and refraction.svg in /home/ga/Documents/"