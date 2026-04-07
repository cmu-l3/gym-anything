#!/bin/bash
echo "=== Setting up galilean_moons_illustrated_report task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

mkdir -p /home/ga/Documents/moons
chown ga:ga /home/ga/Documents/moons

# Download or generate placeholder images for the moons
echo "Downloading moon images..."
wget -q -O /home/ga/Documents/moons/ganymede.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/f/f2/Ganymede_g1_moon_color_usgs.jpg/240px-Ganymede_g1_moon_color_usgs.jpg" || convert -size 240x240 xc:gray -gravity center -draw "circle 120,120 120,20" /home/ga/Documents/moons/ganymede.jpg
wget -q -O /home/ga/Documents/moons/callisto.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/e/e9/Callisto.jpg/240px-Callisto.jpg" || convert -size 240x240 xc:brown -gravity center -draw "circle 120,120 120,20" /home/ga/Documents/moons/callisto.jpg
wget -q -O /home/ga/Documents/moons/io.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/7/7b/Io_highest_resolution_true_color.jpg/240px-Io_highest_resolution_true_color.jpg" || convert -size 240x240 xc:yellow -gravity center -draw "circle 120,120 120,20" /home/ga/Documents/moons/io.jpg
wget -q -O /home/ga/Documents/moons/europa.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/5/54/Europa-discovery.jpg/240px-Europa-discovery.jpg" || convert -size 240x240 xc:white -gravity center -draw "circle 120,120 120,20" /home/ga/Documents/moons/europa.jpg

chown -R ga:ga /home/ga/Documents/moons

# Remove pre-existing document
rm -f /home/ga/Documents/jupiter_moons.odt 2>/dev/null || true

# Task start timestamp
date +%s > /tmp/galilean_moons_start_ts
chmod 666 /tmp/galilean_moons_start_ts

# Close any open activities to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Start Write
echo "Launching Write activity..."
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.AbiWordActivity" &
sleep 12

if pgrep -f "AbiWordActivity\|abiword" > /dev/null 2>&1; then
    echo "Write activity is running"
else
    echo "WARNING: Write activity may not have started"
fi

# Take verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/galilean_moons_start.png" 2>/dev/null || true

echo "=== Setup complete ==="