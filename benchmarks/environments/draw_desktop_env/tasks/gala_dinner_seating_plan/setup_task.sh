#!/bin/bash
set -u

echo "=== Setting up Gala Dinner Seating Plan task ==="

# Define paths
REQ_FILE="/home/ga/Desktop/gala_requirements.txt"
DRAWIO_BIN="drawio"

# Ensure draw.io is available
if ! command -v drawio &>/dev/null; then
    if [ -f /opt/drawio/drawio ]; then
        DRAWIO_BIN="/opt/drawio/drawio"
    elif [ -f /usr/bin/drawio ]; then
        DRAWIO_BIN="/usr/bin/drawio"
    else
        echo "ERROR: draw.io binary not found"
        exit 1
    fi
fi

# 1. Create the Requirements File
echo "Creating requirements file..."
cat > "$REQ_FILE" << 'EOF'
GALA DINNER LAYOUT REQUIREMENTS
===============================
Event: Annual Charity Fundraiser
Room: Grand Ballroom

LAYOUT SPECIFICATIONS:
1. Room Orientation: Portrait or Square.
2. STAGE: Large rectangle centered against the TOP (North) wall.
3. HEAD TABLE: Rectangular table for 6 speakers, placed horizontally in front of the stage.
4. GUEST TABLES: 
   - 6 Round Tables total.
   - Each table must have 8 chairs.
   - Arrange in 2 rows of 3 tables each (behind the Head Table).
   - Label tables 1 through 6 (Row 1: 1-2-3, Row 2: 4-5-6).
5. VIP SEATING: 
   - Tables #1 and #2 are VIP.
   - Highlight these tables with GOLD/YELLOW fill color.
6. OTHER ELEMENTS:
   - ENTRANCE: Bottom-Left corner.
   - BAR: Bottom-Right corner.

TOTAL GUEST COUNT: 54 (48 at guest tables + 6 at head table)
EOF
chown ga:ga "$REQ_FILE"
chmod 644 "$REQ_FILE"

# 2. Clean up previous artifacts
rm -f /home/ga/Desktop/gala_seating_plan.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/gala_seating_plan.png 2>/dev/null || true

# 3. Record start time for anti-gaming
date +%s > /tmp/task_start_timestamp

# 4. Launch draw.io
# We launch without a file to force the startup dialog (Create New/Open Existing).
# We then dismiss it to let the agent handle the "Create New" flow or blank canvas.
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_launch.log 2>&1 &"

# Wait for window
echo "Waiting for draw.io window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "draw.io window detected."
        break
    fi
    sleep 1
done
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss the startup dialog (Esc key) to leave agent with a blank/start screen state
# or let them navigate it. Often Esc on startup dialog creates a blank diagram.
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="