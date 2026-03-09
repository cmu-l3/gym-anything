#!/bin/bash
set -e

echo "=== Setting up Physical Security System Design Task ==="

# 1. Prepare Directories
mkdir -p /home/ga/Desktop
mkdir -p /home/ga/Diagrams
chown -R ga:ga /home/ga/Desktop /home/ga/Diagrams

# 2. Generate the Floor Plan Image (Ground Truth Geometry)
# Using Python/Pillow to ensure consistent layout
cat << 'EOF' > /tmp/gen_floorplan.py
from PIL import Image, ImageDraw, ImageFont
import os

# Canvas
W, H = 1000, 800
img = Image.new("RGB", (W, H), "white")
draw = ImageDraw.Draw(img)

# Styles
wall_color = "black"
wall_width = 8
door_color = "white"
door_width = 12
text_color = "gray"

# 1. Outer Shell
draw.rectangle([50, 50, 950, 750], outline=wall_color, width=wall_width)

# 2. Rooms
# Server Room (Top Left)
draw.rectangle([50, 50, 350, 300], outline=wall_color, width=wall_width)
# IT Closet (Center Left, below Server Room)
draw.rectangle([50, 300, 200, 450], outline=wall_color, width=wall_width)
# R&D Lab (Right Side)
draw.rectangle([550, 50, 950, 750], outline=wall_color, width=wall_width)

# 3. Doors (Draw white lines over walls)
# Main Entry (Bottom Center)
draw.line([400, 750, 500, 750], fill=door_color, width=door_width)
# Server Room Door (Right side of room)
draw.line([350, 200, 350, 250], fill=door_color, width=door_width)
# IT Closet Door (Right side of room)
draw.line([200, 350, 200, 400], fill=door_color, width=door_width)
# R&D Lab Door (Left side of room)
draw.line([550, 350, 550, 450], fill=door_color, width=door_width)
# Emergency Exit (Top Right of Lab)
draw.line([900, 50, 950, 50], fill=door_color, width=door_width)

# 4. Labels
try:
    # Attempt to load a better font, fallback to default
    font = ImageFont.load_default()
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 24)
    except:
        pass
        
    draw.text((100, 100), "SERVER ROOM\n(High Security)", fill="red", font=font)
    draw.text((70, 350), "IT CLOSET", fill="black", font=font)
    draw.text((650, 200), "SECURE R&D LAB", fill="blue", font=font)
    draw.text((420, 600), "LOBBY / HALLWAY", fill="black", font=font)
    draw.text((420, 760), "MAIN ENTRY", fill="black", font=font)
except Exception as e:
    print(f"Font error: {e}")

img.save("/home/ga/Desktop/lab_floorplan.png")
print("Floorplan generated successfully.")
EOF

# Run generation script
python3 /tmp/gen_floorplan.py
chown ga:ga /home/ga/Desktop/lab_floorplan.png

# 3. Generate Requirements Document
cat << 'EOF' > /home/ga/Desktop/security_requirements.txt
PHYSICAL SECURITY DESIGN REQUIREMENTS
PROJECT: PROTOTYPE LAB FACILITY

Please design the security overlay for the new facility. 
Place devices on the floor plan and connect them all to the Control Panel with cabling lines.

REQUIRED DEVICES:

1. IT CLOSET
   - 1x Security Control Panel (Main Controller)

2. MAIN ENTRY
   - 1x Card Reader (Exterior)
   - 1x Door Contact Sensor
   - 1x Dome Camera (Viewing entrance)

3. SERVER ROOM
   - 1x Biometric/Card Reader
   - 1x Door Contact Sensor
   - 1x Camera (Viewing rack area)

4. SECURE R&D LAB
   - 1x Card Reader
   - 1x Door Contact Sensor
   - 1x Motion Sensor (Corner mount)

5. EMERGENCY EXIT (Top Right)
   - 1x Door Contact Sensor
   - 1x Motion Sensor (PIR)

TOTALS:
- 1 Panel
- 3 Readers
- 4 Door Contacts
- 2 Motion Sensors
- 2 Cameras
EOF
chown ga:ga /home/ga/Desktop/security_requirements.txt

# 4. Cleanup Previous State
rm -f /home/ga/Diagrams/security_design.drawio
rm -f /home/ga/Diagrams/security_design.pdf
rm -f /tmp/task_result.json

# 5. Launch Application
echo "Launching draw.io..."
# Start process
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox > /dev/null 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        echo "draw.io started."
        break
    fi
    sleep 1
done

# 6. Handle "Update Available" Dialog (Aggressive Dismissal)
# This dialog often blocks the UI on startup
sleep 3
echo "Dismissing potential update dialogs..."
for i in {1..5}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Record Start Time
date +%s > /tmp/task_start_time.txt

# 8. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="