#!/bin/bash
set -e

echo "=== Setting up Film Set Lighting Plot Task ==="

# 1. Prepare Directories
mkdir -p /home/ga/Diagrams
mkdir -p /home/ga/Desktop

# 2. Create the DP Scene Notes
cat > /home/ga/Desktop/dp_scene_notes.txt << 'EOF'
FROM: Chivo (DP)
TO: Sparky (Gaffer)
SUBJECT: Scene 54 - Interrogation Room - Lighting Plan

Hey, here's the plan for the Interrogation scene tomorrow. Need you to draw up the plot for the rigging crew.

LOCATION INFO:
- Room is 20ft wide (North wall) x 15ft deep (East wall).
- Door is on the East wall, bottom corner.
- Large Window is on the North wall, center.

BLOCKING:
- Table in the center of the room.
- SUSPECT is seated at the North side of table (back to window).
- DETECTIVE is seated at the South side of table (facing window).

LIGHTING ORDER:
1. L1 (Key Light for Detective): Arri Skypanel S60. Place it Stage Right (West), 45 degrees to the Detective. Set to 5600K.
2. L2 (Back Light for Detective): 650w Fresnel. Hang from grid, directly behind Detective. Gel: 1/2 CTO.
3. L3 (Rim Light for Suspect): ETC Source 4 Leko (19 deg). Place outside the window (North) shooting in. Gel: CTB (Course Blue).
4. L4 (Fill Light): 4x4 Bounce Board with a 1K Open Face hitting it. Place Stage Left (East).
5. L5 (Practical): Desk Lamp on the table. Dimmer channel 1.

POWER:
- Run all stingers (cables) to the 600A Distro Box in the South-East corner.

LEGEND:
- Make sure to include a legend box so the new guys know which symbol is which (Fresnel, Leko, Panel, Actor).
EOF

# Set permissions
chown ga:ga /home/ga/Desktop/dp_scene_notes.txt
chmod 644 /home/ga/Desktop/dp_scene_notes.txt

# 3. Clean up previous runs
rm -f /home/ga/Diagrams/lighting_plot_scene54.drawio
rm -f /home/ga/Diagrams/lighting_plot_scene54.pdf

# 4. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 5. Launch draw.io to ensure it's ready
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox > /dev/null 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done

# Dismiss update dialogs if they appear (common issue)
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 6. Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="