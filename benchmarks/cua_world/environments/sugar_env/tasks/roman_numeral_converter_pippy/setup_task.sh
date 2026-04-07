#!/bin/bash
echo "=== Setting up roman_numeral_converter_pippy task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists and has correct permissions
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing output files to ensure the agent creates them fresh
rm -f /home/ga/Documents/roman_numerals.txt 2>/dev/null || true
rm -f /home/ga/Documents/roman_numerals.html 2>/dev/null || true

# Record task start timestamp for mtime validation (anti-gaming)
date +%s > /tmp/roman_numeral_start_ts
chmod 666 /tmp/roman_numeral_start_ts

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Verify Sugar desktop is running
if ! pgrep -f "jarabe.main" > /dev/null 2>&1; then
    echo "Sugar session not found, restarting..."
    systemctl restart gdm 2>/dev/null || true
    sleep 15
fi

# Take a verification screenshot of the initial state
su - ga -c "$SUGAR_ENV scrot /tmp/pippy_task_start.png" 2>/dev/null || true

echo "=== roman_numeral_converter_pippy task setup complete ==="
echo "Sugar home view is ready."
echo "Agent must open Pippy, write the conversion program, and generate both TXT and HTML files in /home/ga/Documents/."