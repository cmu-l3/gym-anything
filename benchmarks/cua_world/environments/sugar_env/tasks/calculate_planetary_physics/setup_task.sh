#!/bin/bash
# Do NOT use set -e to prevent premature exit on expected failures
echo "=== Setting up calculate_planetary_physics task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing results file to ensure agent creates it fresh
rm -f /home/ga/Documents/orbital_results.txt 2>/dev/null || true

# Close any open activity first to return to home view safely
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Ensure Sugar home view is visible
if ! pgrep -f "jarabe.main" > /dev/null 2>&1; then
    echo "Sugar session not found, restarting GDM..."
    systemctl restart gdm 2>/dev/null || true
    sleep 15
fi

# Record task start timestamp for mtime and anti-gaming validation
date +%s > /tmp/calculate_planetary_physics_start_ts
chmod 666 /tmp/calculate_planetary_physics_start_ts

# Take a verification screenshot of initial state
su - ga -c "$SUGAR_ENV scrot /tmp/calculate_task_start.png" 2>/dev/null || true

echo "=== calculate_planetary_physics task setup complete ==="
echo "Sugar desktop is ready at home view."
echo "Agent must compute orbital/escape velocities in Calculate, journal it, and save text file via Terminal."