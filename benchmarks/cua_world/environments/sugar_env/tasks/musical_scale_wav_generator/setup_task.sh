#!/bin/bash
echo "=== Setting up musical_scale_wav_generator task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing files
rm -f /home/ga/Documents/c_major_scale.wav 2>/dev/null || true
rm -f /home/ga/Documents/note_frequencies.txt 2>/dev/null || true

# Record task start timestamp for mtime validation
date +%s > /tmp/musical_scale_start_ts
chmod 666 /tmp/musical_scale_start_ts

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch the Pippy activity
echo "Launching Pippy activity..."
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.Pippy" &
sleep 12

# Take a verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/musical_scale_start.png" 2>/dev/null || true

echo "=== setup complete ==="