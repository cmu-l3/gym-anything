#!/bin/bash
set -e
echo "=== Setting up Aviation IAP Profile View Task ==="

# 1. Create Directories
mkdir -p /home/ga/Desktop
mkdir -p /home/ga/Diagrams
chown -R ga:ga /home/ga/Desktop /home/ga/Diagrams

# 2. Create the Data Source File (Real World Data)
DATA_FILE="/home/ga/Desktop/iap_data.txt"
cat > "$DATA_FILE" << 'EOF'
INSTRUMENT APPROACH PROCEDURE DATA
AIRPORT: SAN FRANCISCO INTL (KSFO)
PROCEDURE: ILS or LOC RWY 28R
--------------------------------------------------
PROFILE VIEW DATA:

1. INTERMEDIATE FIX (IF)
   Name: ARCHI
   Distance: 11.9 DME (from I-SFO) / 7.0 NM from FAF
   Mandatory Altitude: 4000 feet
   Note: Level flight segment to DUMBA

2. FINAL APPROACH FIX (FAF) / GLIDESLOPE INTERCEPT
   Name: DUMBA
   Distance: 5.4 DME (from I-SFO)
   Mandatory Altitude: 1800 feet
   Symbol: Maltese Cross (Non-precision) / Lightning Bolt (GS intercept)

3. RUNWAY THRESHOLD (MAP)
   Name: RWY 28R
   Distance: 0 NM
   Touchdown Zone Elevation: 13 feet

4. GLIDESLOPE
   Angle: 3.00 degrees
   Path: Descends from DUMBA (1800') to RWY

5. MISSED APPROACH
   Instruction: Climb to 3000
   Graphic: Dashed arrow curving upward from runway

6. RADIO
   ILS Frequency: I-SFO 111.7
--------------------------------------------------
EOF
chown ga:ga "$DATA_FILE"
chmod 644 "$DATA_FILE"

# 3. Clean previous artifacts
rm -f /home/ga/Diagrams/ksfo_ils_28r_profile.drawio
rm -f /home/ga/Diagrams/ksfo_ils_28r_profile.pdf
rm -f /tmp/task_result.json

# 4. Record Start Time
date +%s > /tmp/task_start_time.txt

# 5. Launch Application
# We launch it so the agent doesn't have to hunt for the executable,
# but we leave the "Create New Diagram" step to the agent as part of the task workflow.
if ! pgrep -f "drawio" > /dev/null; then
    echo "Starting diagrams.net..."
    su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox &"
fi

# 6. Handle "Update Available" dialog if it blocks startup
# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        echo "Window detected, checking for dialogs..."
        sleep 2
        # Press Escape a few times to dismiss potential update dialogs
        DISPLAY=:1 xdotool key Escape
        sleep 0.5
        DISPLAY=:1 xdotool key Escape
        break
    fi
    sleep 1
done

# 7. Maximize Window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "draw.io" 2>/dev/null || true

# 8. Initial Screenshot
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="