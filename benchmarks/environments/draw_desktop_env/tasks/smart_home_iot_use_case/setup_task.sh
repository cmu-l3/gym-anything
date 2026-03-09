#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero

echo "=== Setting up smart_home_iot_use_case task ==="

# Find draw.io binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then
    DRAWIO_BIN="drawio"
elif [ -f /opt/drawio/drawio ]; then
    DRAWIO_BIN="/opt/drawio/drawio"
elif [ -f /usr/bin/drawio ]; then
    DRAWIO_BIN="/usr/bin/drawio"
fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found!"
    exit 1
fi

# Clean up any existing output files
rm -f /home/ga/Desktop/securehub_usecase.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/securehub_usecase.png 2>/dev/null || true

# Create the Requirements Document
cat > /home/ga/Desktop/iot_requirements.txt << 'EOF'
SecureHub IoT System - Functional Requirements
==============================================

Product Overview:
The SecureHub is a central home automation controller focusing on security.

System Actors:
1. Homeowner (Primary User): Has full access to all features.
2. Guest User: Limited access (can view cameras but not change settings).
3. Emergency Services: External entity notified during alarms.
4. Cloud Backend: External system for logging and updates.

Functional Requirements (Use Cases):

A. Core Security
   - The Homeowner must be able to "Arm/Disarm System".
   - Critical Action: To ensuring security, "Arm/Disarm System" MUST automatically include "Authenticate User" (PIN/Biometric).
   - The Homeowner can "Trigger Panic Alarm" manually.
   - If the Panic Alarm is triggered in silent mode, the system extends this behavior to optionally "Notify Police".

B. Access Control
   - The Homeowner can "Unlock Door" remotely.
   - Safety Requirement: "Unlock Door" MUST include "Authenticate User" validation.
   - The Homeowner can "Manage Access Codes" for guests.

C. Monitoring
   - Both Homeowner and Guest User can "View Camera Feed".
   - The system automatically runs "Sync Logs" with the Cloud Backend in the background.

Diagramming Instructions:
- Use standard UML Use Case notation.
- Use Stick Figures for Actors.
- Use Ellipses for Use Cases.
- Enclose Use Cases in a System Boundary rectangle.
- Use dashed arrows with <<include>> and <<extend>> labels for specific relationships described above.
EOF

chown ga:ga /home/ga/Desktop/iot_requirements.txt
chmod 644 /home/ga/Desktop/iot_requirements.txt
echo "Requirements file created at ~/Desktop/iot_requirements.txt"

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Launch draw.io (startup dialog will appear)
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_launch.log 2>&1 &"

# Wait for draw.io window
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Additional wait for UI to fully load
sleep 5

# Maximize the window for consistent layout
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss startup dialog (creates blank diagram)
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape
sleep 2

# Verify draw.io is running
if pgrep -f "drawio" > /dev/null; then
    echo "draw.io is running"
else
    echo "Warning: draw.io may not have started properly"
fi

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="