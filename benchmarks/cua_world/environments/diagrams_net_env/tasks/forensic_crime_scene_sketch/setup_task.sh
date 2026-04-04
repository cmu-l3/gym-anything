#!/bin/bash
set -e

echo "=== Setting up Forensic Crime Scene Sketch Task ==="

# 1. Prepare Directories
mkdir -p /home/ga/Desktop/case_files
mkdir -p /home/ga/Diagrams
chown -R ga:ga /home/ga/Desktop/case_files /home/ga/Diagrams

# 2. Generate Field Notes
cat > /home/ga/Desktop/case_files/field_notes_402.txt << 'EOF'
CASE FILE: 402 - BURGLARY/ASSAULT
DATE: 2024-05-12
LOCATION: Room 402
OFFICER: Sgt. J. Miller

REQUEST:
Please digitize the crime scene sketch for the jury presentation.
Precision is critical. Use the scale provided below.

SCALE REQUIREMENT:
1 Meter = 50 Pixels

ROOM GEOMETRY:
- The room is a rectangular shape.
- Width (East-West): 6.0 meters
- Depth (North-South): 4.5 meters
- Origin Point (0,0): North-West Corner of the room interior.
- Door: Located on the North Wall. Starts 1.0 meter from the NW corner. Door width is 1.0 meter.

EVIDENCE LOG (Coordinates measured from NW Corner Origin):
1. Marker A (Spent Casing):
   - 2.5 meters East
   - 1.5 meters South
   - Shape: Circle/Ellipse with label "A"

2. Marker B (Discarded Weapon - Hammer):
   - 2.8 meters East
   - 1.6 meters South
   - Shape: Circle/Ellipse with label "B"

3. Marker C (Blood Spatter):
   - 3.5 meters East
   - 2.0 meters South
   - Shape: Circle/Ellipse with label "C"

4. Victim (Position of Head):
   - 4.0 meters East
   - 2.5 meters South
   - Shape: Rectangle or "Actor" shape with label "Victim"

OUTPUT REQUIREMENTS:
- Save source file to: ~/Diagrams/case_402_sketch.drawio
- Export PDF to: ~/Diagrams/case_402_exhibit.pdf
- Include text label: "Scale: 1m = 50px"
EOF
chown ga:ga /home/ga/Desktop/case_files/field_notes_402.txt

# 3. Clean previous artifacts
rm -f /home/ga/Diagrams/case_402_sketch.drawio
rm -f /home/ga/Diagrams/case_402_exhibit.pdf

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

# 5. Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox > /dev/null 2>&1 &"

# 6. Wait for window and dismiss update dialogs
echo "Waiting for draw.io window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        break
    fi
    sleep 1
done

echo "Attempting to dismiss update dialogs..."
sleep 5
# Press Escape a few times to dismiss "Update Available" or "Open File" dialogs
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape
    sleep 0.5
done

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Open the field notes text file for the user to see
su - ga -c "DISPLAY=:1 xdg-open /home/ga/Desktop/case_files/field_notes_402.txt" &

# 8. Take initial screenshot
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="