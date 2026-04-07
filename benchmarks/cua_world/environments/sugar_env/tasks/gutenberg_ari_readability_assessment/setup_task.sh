#!/bin/bash
echo "=== Setting up Gutenberg Readability task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Clean up any pre-existing files
rm -f /home/ga/Documents/ari_calculator.py 2>/dev/null || true
rm -f /home/ga/Documents/alice_review.odt 2>/dev/null || true

# Ensure alice in wonderland exists
if [ ! -f /home/ga/Documents/alice_in_wonderland.txt ]; then
    echo "Downloading alice in wonderland..."
    wget -q -O /home/ga/Documents/alice_in_wonderland.txt "https://www.gutenberg.org/cache/epub/11/pg11.txt" || echo "Download failed"
    chown ga:ga /home/ga/Documents/alice_in_wonderland.txt
fi

date +%s > /tmp/readability_start_ts
chmod 666 /tmp/readability_start_ts

# Return to home view by closing active windows gracefully
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Take verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/readability_start.png" 2>/dev/null || true

echo "=== Setup complete ==="