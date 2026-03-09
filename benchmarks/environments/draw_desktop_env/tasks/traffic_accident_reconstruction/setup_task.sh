#!/bin/bash
# Setup script for Traffic Accident Reconstruction task

echo "=== Setting up Traffic Accident Reconstruction Task ==="

# Source shared utilities if available, otherwise define basics
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# 1. Create the Police Incident Report on the Desktop
cat > /home/ga/Desktop/police_report_XA9920.txt << 'EOF'
POLICE INCIDENT REPORT
Case Number: XA-9920
Date: 2023-10-15
Time: 14:30
Officer: Sgt. J. Miller #442

LOCATION:
Intersection of Main Street and Elm Avenue.
- Main Street: Runs North-South. 4 lanes total (2 Northbound, 2 Southbound).
- Elm Avenue: Runs East-West. 2 lanes total (1 Eastbound, 1 Westbound).
- Signalized intersection.

VEHICLES INVOLVED:
Unit 1 (Claimant):
- Vehicle: 2018 Honda Accord (Blue)
- Driver: Sarah Jenkins
- Direction of Travel: Northbound on Main St, Lane 1 (inside lane).
- Intent: Proceeding straight through intersection.

Unit 2 (Insured):
- Vehicle: 2020 Ford F-150 (Red)
- Driver: Mike Ross
- Direction of Travel: Southbound on Main St.
- Intent: Turning LEFT onto Elm Ave (Eastbound).

INCIDENT DESCRIPTION:
Unit 2 attempted to make a left turn onto Elm Ave from Southbound Main St. Unit 2 failed to yield right of way to Unit 1, which was proceeding Northbound on Main St with a green light.

POINT OF IMPACT:
Front of Unit 1 struck the Passenger Side (Right Side) of Unit 2.
Unit 2 was positioned at approximately a 45-degree angle in the center of the intersection at the moment of impact.

DIAGRAMMING REQUIREMENTS:
- Show roadway layout with labeled streets.
- Indicate North.
- Depict vehicles as rectangles color-coded (Unit 1=Blue, Unit 2=Red).
- Show vehicles at Point of Impact.
EOF

chown ga:ga /home/ga/Desktop/police_report_XA9920.txt
chmod 644 /home/ga/Desktop/police_report_XA9920.txt
echo "Created police report at /home/ga/Desktop/police_report_XA9920.txt"

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Launch draw.io
echo "Launching draw.io..."
DRAWIO_BIN="drawio"
if [ -f /opt/drawio/drawio ]; then DRAWIO_BIN="/opt/drawio/drawio"; fi

# Clean up any previous runs
pkill -f drawio 2>/dev/null || true
rm -f /home/ga/Desktop/accident_reconstruction.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/accident_reconstruction.png 2>/dev/null || true

# Launch
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_launch.log 2>&1 &"

# Wait for window
echo "Waiting for draw.io window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done
sleep 3

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss startup dialog (Escape) to create blank diagram
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape
sleep 2

# 4. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="