#!/bin/bash
set -e

echo "=== Setting up WiFi Coverage Heatmap task ==="

# 1. Create Directories
mkdir -p /home/ga/Desktop
mkdir -p /home/ga/Diagrams/exports
chown -R ga:ga /home/ga/Desktop /home/ga/Diagrams

# 2. Generate Floorplan Image using Python (Pillow)
# We generate this dynamically to ensure it exists and matches specs
cat << 'PY_EOF' > /tmp/generate_floorplan.py
from PIL import Image, ImageDraw, ImageFont

# Create white canvas 800x600
img = Image.new('RGB', (800, 600), color='white')
d = ImageDraw.Draw(img)

# Draw Walls (Black lines, thickness 5)
# Outer walls
d.rectangle([50, 50, 750, 550], outline='black', width=5)

# Internal walls
# Reception/Lobby area (Top Left)
d.line([50, 250, 250, 250], fill='black', width=3)
d.line([250, 50, 250, 250], fill='black', width=3)

# Conference Room (Bottom Left)
d.line([50, 400, 300, 400], fill='black', width=3)
d.line([300, 550, 300, 400], fill='black', width=3)

# IT Server Room (Small, Top Right)
d.line([600, 50, 600, 150], fill='black', width=3)
d.line([600, 150, 750, 150], fill='black', width=3)

# Bullpen / Open Office (Center/Right) - just open space

# Add Text Labels
try:
    # Try to load a default font, fall back to default if needed
    font = ImageFont.truetype("DejaVuSans.ttf", 20)
except IOError:
    font = ImageFont.load_default()

d.text((100, 150), "LOBBY", fill='gray', font=font)
d.text((100, 475), "CONFERENCE", fill='gray', font=font)
d.text((100, 500), "ROOM", fill='gray', font=font)
d.text((620, 100), "SERVER", fill='gray', font=font)
d.text((450, 300), "OPEN OFFICE / BULLPEN", fill='gray', font=font)

img.save("/home/ga/Desktop/office_floorplan.png")
print("Floorplan generated.")
PY_EOF

# Execute generation
python3 /tmp/generate_floorplan.py
chown ga:ga /home/ga/Desktop/office_floorplan.png

# 3. Create Project Specs Text File
cat << 'TXT_EOF' > /home/ga/Desktop/wifi_project_specs.txt
PROJECT: Office WiFi Upgrade
DATE: 2024-10-24
ENGINEER: Agent

REQUIREMENTS:
1. LAYER SETUP:
   - Import 'office_floorplan.png' to a bottom layer named "Floor Plan".
   - LOCK the "Floor Plan" layer so it cannot be moved.
   - Create a layer named "Hardware" for devices.
   - Create a layer named "Coverage" for signal heatmaps (top layer).

2. HARDWARE PLACEMENT (Hardware Layer):
   - Place a "Wireless Access Point" icon in the LOBBY (Top Left).
   - Place a "Wireless Access Point" icon in the CONFERENCE ROOM (Bottom Left).
   - Place a "Wireless Access Point" icon in the OPEN OFFICE / BULLPEN (Center).

3. COVERAGE VISUALIZATION (Coverage Layer):
   - Draw a circle around each AP to represent signal coverage.
   - 5GHz Coverage: Green Fill.
   - 2.4GHz Coverage: Blue Fill (optional/secondary).
   - CRITICAL: Coverage shapes must be SEMI-TRANSPARENT (Opacity ~30-50%) 
     so the floor plan is visible underneath.

4. EXPORT:
   - Save source as 'wifi_project.drawio' in ~/Diagrams.
   - Export final map as 'wifi_coverage_map.png' in ~/Diagrams/exports.
TXT_EOF
chown ga:ga /home/ga/Desktop/wifi_project_specs.txt

# 4. Clean up previous runs
rm -f /home/ga/Diagrams/wifi_project.drawio
rm -f /home/ga/Diagrams/exports/wifi_coverage_map.png

# 5. Launch draw.io
echo "Launching draw.io..."
# We launch cleanly; agent must do the import.
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done

# Dismiss update dialogs aggressively
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Capture Initial State
date +%s > /tmp/task_start_time.txt
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="