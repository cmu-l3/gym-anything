#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero harmlessly

echo "=== Setting up apartment_floorplan_listing task ==="

# 1. timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Create the specifications file
cat > /home/ga/Desktop/apartment_specs.txt << 'EOF'
APARTMENT FLOOR PLAN SPECIFICATIONS
====================================
Building: MiMA Tower, 450 West 42nd Street, Manhattan, NY 10036
Unit Type: 2BR/2BA Corner Unit, Floor 38
Total Area: ~1,150 sq ft
Orientation: North-facing living room with floor-to-ceiling windows

ROOM LAYOUT (approximate dimensions):
--------------------------------------
1. Entry Foyer:        10' x 5'    - Front door (hinged, swings in)
2. Living/Dining Room: 18' x 14'   - 2 floor-to-ceiling windows (north wall)
3. Kitchen:            12' x 8'    - Open to living room (no door), one window (west wall)
4. Master Bedroom:     14' x 12'   - 1 door from hallway, 1 window (east wall)
5. Master Bathroom:     8' x 6'    - 1 door from master bedroom
6. Walk-in Closet:      6' x 4'    - 1 door from master bedroom
7. Second Bedroom:     12' x 10'   - 1 door from hallway, 1 window (north wall)
8. Second Bathroom:     7' x 5'    - 1 door from hallway

SPATIAL ADJACENCY:
------------------
- Entry Foyer connects to a central Hallway running east-west
- Living/Dining Room is north of the Hallway, accessed from the Foyer/Hallway
- Kitchen is west of and open to the Living/Dining Room
- Master Bedroom is at the east end of the Hallway
- Walk-in Closet and Master Bathroom open off the Master Bedroom
- Second Bedroom is northeast, off the Hallway
- Second Bathroom is off the Hallway between the two bedrooms

REQUIRED FURNITURE:
-------------------
- Living Room: Sofa, Coffee Table, TV/Entertainment unit, Dining Table with 4 chairs
- Kitchen: Counter/Island, Sink, Stove/Range, Refrigerator
- Master Bedroom: Queen/King Bed, 2 Nightstands, Dresser
- Master Bathroom: Bathtub/Shower, Toilet, Vanity/Sink
- Second Bedroom: Double Bed, Desk, Nightstand
- Second Bathroom: Shower stall, Toilet, Sink

ANNOTATIONS REQUIRED:
---------------------
- Every room labeled with room name and dimensions (e.g., "Master Bedroom\n14' x 12'")
- Title block: "Unit 38F - 2BR/2BA - 1,150 sq ft - MiMA Tower"
- North arrow indicator
EOF

chown ga:ga /home/ga/Desktop/apartment_specs.txt
chmod 644 /home/ga/Desktop/apartment_specs.txt

# 3. Clean up previous run artifacts
rm -f /home/ga/Desktop/apartment_floorplan.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/apartment_floorplan.png 2>/dev/null || true

# 4. Find draw.io binary
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

# 5. Launch draw.io
echo "Launching draw.io..."
# Launch with update disabled to prevent update popups
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_launch.log 2>&1 &"

# 6. Wait for window
echo "Waiting for draw.io window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done

# 7. Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Dismiss startup dialog to get blank canvas
# draw.io Desktop starts with a "Create New / Open Existing" dialog.
# Pressing Escape usually dismisses it or cancels the "Open" flow, landing on a blank diagram or allowing new creation.
sleep 3
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
# Just in case it needs a second Escape (sometimes one closes a modal, second focuses canvas)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 9. Focus the window
DISPLAY=:1 wmctrl -a "draw.io" 2>/dev/null || true

# 10. Initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="