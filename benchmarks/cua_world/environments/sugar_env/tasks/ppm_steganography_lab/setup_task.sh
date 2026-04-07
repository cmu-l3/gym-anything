#!/bin/bash
echo "=== Setting up PPM Steganography Task ==="

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# Create the cover image in pure python to ensure exact P3 token matching (no comments)
python3 << 'PYEOF'
import os
os.makedirs("/home/ga/Documents", exist_ok=True)
with open("/home/ga/Documents/cover_image.ppm", "w") as f:
    f.write("P3\n200 200\n255\n")
    for i in range(200):
        line = []
        for j in range(200):
            # Procedural texture gradient
            line.append(f"{(i*2)%256} {(j*2)%256} {(i+j)%256}")
        f.write(" ".join(line) + "\n")
PYEOF

chown -R ga:ga /home/ga/Documents

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch Terminal activity for scripting
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.Terminal" &
sleep 5

# Ensure it is maximized
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot of environment
su - ga -c "$SUGAR_ENV scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Setup complete ==="