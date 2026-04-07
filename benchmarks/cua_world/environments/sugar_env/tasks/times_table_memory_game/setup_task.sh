#!/bin/bash
# Do NOT use set -e
echo "=== Setting up times_table_memory_game task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Record task start timestamp
date +%s > /tmp/times_table_memory_game_start_ts
chmod 666 /tmp/times_table_memory_game_start_ts

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Ensure Sugar home view is visible
if ! pgrep -f "jarabe.main" > /dev/null 2>&1; then
    echo "Sugar session not found, restarting..."
    systemctl restart gdm 2>/dev/null || true
    sleep 15
fi

# Launch the Memorize activity
echo "Launching Memorize activity..."
su - ga -c "$SUGAR_ENV sugar-launch sugar-memorize-activity" &
sleep 12

# Check if Memorize is running
if pgrep -f "memorize\|Memorize" > /dev/null 2>&1; then
    echo "Memorize activity is running"
else
    echo "WARNING: Memorize activity may not have started"
fi

# Take verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/memorize_task_start.png" 2>/dev/null || true

echo "=== times_table_memory_game task setup complete ==="
echo "Memorize activity is open."
echo "Agent must create 8 card pairs for 6x table and save as '6 Times Table Game'"
