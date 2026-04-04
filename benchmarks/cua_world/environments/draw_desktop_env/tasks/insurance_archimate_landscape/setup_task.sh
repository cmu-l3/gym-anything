#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero harmlessly

echo "=== Setting up insurance_archimate_landscape task ==="

# 1. Define Environment Variables
export DISPLAY=${DISPLAY:-:1}
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

# 2. Clean up previous run artifacts
rm -f /home/ga/Desktop/claims_architecture.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/claims_architecture.png 2>/dev/null || true

# 3. Create the Architecture Definition File
# Based on the ArchiSurance Case Study (The Open Group)
cat > /home/ga/Desktop/archisurance_definition.txt << 'EOF'
=== ArchiSurance Claims Architecture Definition ===

Please model the following elements using ArchiMate 3.1 notation.
Organize them into three horizontal layers: Business (top), Application (middle), Technology (bottom).

BUSINESS LAYER (Yellow):
1. Element: "Customer" | Type: Business Actor
2. Element: "Submit Claim" | Type: Business Process
   - Relationship: "Customer" is assigned to "Submit Claim"
3. Element: "Damage Report" | Type: Business Object
   - Relationship: "Submit Claim" accesses "Damage Report"

APPLICATION LAYER (Blue):
1. Element: "Claims Intake Service" | Type: Application Service
   - Relationship: Serves "Submit Claim" process
2. Element: "Policy Administration System" | Type: Application Component
   - Relationship: Realizes "Claims Intake Service"
3. Element: "Document Management System" | Type: Application Component
   - Relationship: "Policy Administration System" flows data to "Document Management System"

TECHNOLOGY LAYER (Green):
1. Element: "Mainframe" | Type: Node
   - Relationship: Hosts "Policy Administration System"
2. Element: "DB2 Database" | Type: System Software
   - Relationship: "Mainframe" hosts "DB2 Database"
   - Relationship: "Policy Administration System" accesses "DB2 Database"
3. Element: "Claim PDF" | Type: Artifact
   - Relationship: "Document Management System" accesses "Claim PDF"
EOF

chown ga:ga /home/ga/Desktop/archisurance_definition.txt
echo "Created definition file at /home/ga/Desktop/archisurance_definition.txt"

# 4. Record Task Start Time
date +%s > /tmp/task_start_timestamp

# 5. Launch draw.io Desktop
echo "Launching draw.io..."
# Use --disable-update to prevent update popups
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_launch.log 2>&1 &"

# 6. Wait for Window and Initialize
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Wait extra time for UI to settle
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss "Create New / Open Existing" dialog with Escape to get blank canvas
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape
sleep 2

# Take initial screenshot for evidence
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="