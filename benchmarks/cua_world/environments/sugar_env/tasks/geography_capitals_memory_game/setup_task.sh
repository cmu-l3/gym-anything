#!/bin/bash
# Setup script for geography_capitals_memory_game
echo "=== Setting up geography_capitals_memory_game task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Record task start timestamp for anti-gaming (checking for new files)
date +%s > /tmp/geography_task_start_ts
chmod 666 /tmp/geography_task_start_ts

# Close any open activity first to return to the home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Ensure Sugar home view is visible; restart GDM if it crashed
if ! pgrep -f "jarabe.main" > /dev/null 2>&1; then
    echo "Sugar session not found, restarting..."
    systemctl restart gdm 2>/dev/null || true
    sleep 15
fi

# Launch the Memorize activity directly
echo "Launching Memorize activity..."
su - ga -c "$SUGAR_ENV sugar-launch sugar-memorize-activity" &
sleep 12

# Check if Memorize is actually running
if pgrep -f "memorize\|Memorize" > /dev/null 2>&1; then
    echo "Memorize activity is running."
else
    echo "WARNING: Memorize activity may not have started properly."
fi

# Take a verification screenshot of the initial state
su - ga -c "$SUGAR_ENV scrot /tmp/memorize_geography_task_start.png" 2>/dev/null || true

echo "=== geography_capitals_memory_game task setup complete ==="
echo "Memorize activity is open."
echo "Agent must create 8 card pairs for South American countries/capitals and save as 'South American Capitals'."