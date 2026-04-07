#!/bin/bash
set -euo pipefail

echo "=== Setting up Residential Floor Plan Task ==="

# 1. Kill any existing LibreCAD instance
pkill -f librecad 2>/dev/null || true
sleep 2

# 2. Clean up previous outputs and prepare directories
DOCS_DIR="/home/ga/Documents/LibreCAD"
mkdir -p "$DOCS_DIR"
rm -f "$DOCS_DIR/apartment_plan.dxf"
rm -f "$DOCS_DIR/apartment_brief.txt"

# 3. Record task start time (AFTER cleanup)
date +%s > /tmp/task_start_time.txt

# 4. Generate the architectural brief specification file
cat > "$DOCS_DIR/apartment_brief.txt" << 'EOF'
=============================================
RESIDENTIAL FLOOR PLAN - ARCHITECTURAL BRIEF
=============================================
Project:   Maple Street Apartments, Unit 2B
Architect: Chen & Associates
Date:      2024-06-15
Scale:     1/4" = 1'-0"
Units:     Feet (1 drawing unit = 1 foot)

---------------------------------------------
UNIT SUMMARY
---------------------------------------------
  Type:      2 Bedroom / 1 Bathroom
  Gross Area: 660 sq ft
  Exterior:  30'-0" wide x 22'-0" deep
  Origin:    Southwest corner at (0, 0)

---------------------------------------------
ROOM SCHEDULE
---------------------------------------------
  Room          Width   Depth   Area     Coordinates
  Living Room   18'     12'     216 sf   (0,10) to (18,22)
  Kitchen       12'     12'     144 sf   (18,10) to (30,22)
  Bedroom 1     12'     10'     120 sf   (0,0) to (12,10)
  Bathroom       6'     10'      60 sf   (12,0) to (18,10)
  Bedroom 2     12'     10'     120 sf   (18,0) to (30,10)

---------------------------------------------
INTERIOR WALL POSITIONS
---------------------------------------------
  1. Horizontal wall at Y = 10  (full width, X = 0 to 30)
  2. Vertical wall at X = 12    (lower section, Y = 0 to 10)
  3. Vertical wall at X = 18    (full height, Y = 0 to 22)

  Note: All walls are drawn as single lines (partition
  centerlines). Leave gaps for all door and window openings.

---------------------------------------------
DOOR SCHEDULE
---------------------------------------------
  Mark  Location                Width   Swing Direction
  D1    North wall, X = 9      3'-0"   South into Living Room
  D2    X=18 wall, Y = 16      3'-0"   East into Kitchen
  D3    Y=10 wall, X = 6       3'-0"   South into Bedroom 1
  D4    Y=10 wall, X = 15      2'-8"   South into Bathroom
  D5    Y=10 wall, X = 24      3'-0"   South into Bedroom 2

  Representation: 90-degree arc swing from wall line into room.

---------------------------------------------
WINDOW SCHEDULE
---------------------------------------------
  Mark  Wall              Center   Width
  W1    West  (Living)    Y = 16   5'-0"
  W2    East  (Kitchen)   Y = 16   4'-0"
  W3    South (Bedroom 1) X = 6    4'-0"
  W4    East  (Bedroom 2) Y = 5    4'-0"

  Representation: Pair of short parallel lines in opening.

---------------------------------------------
FIXTURE REQUIREMENTS
---------------------------------------------
  Kitchen (on FIXTURES layer):
    - Counter rectangle along the east wall
    - Sink (circle) on counter
    - Stove rectangle on counter

  Bathroom (on FIXTURES layer):
    - Bathtub rectangle along one wall
    - Toilet rectangle
    - Sink circle

---------------------------------------------
LAYER STANDARDS
---------------------------------------------
  Layer Name   Color Index  Color    Usage
  WALLS        7            White    All wall lines
  DOORS        1            Red      Door arc swings
  WINDOWS      4            Cyan     Window line pairs
  FIXTURES     3            Green    Kitchen & bath fixtures
  DIMENSIONS   2            Yellow   Room dimensions
  TEXT         6            Magenta  Room name labels

---------------------------------------------
DIMENSION REQUIREMENTS
---------------------------------------------
  Minimum 10 linear dimensions including:
    - Overall building width (30')
    - Overall building height (22')
    - Individual room widths and heights
    - Representative door or window widths

---------------------------------------------
LABEL REQUIREMENTS
---------------------------------------------
  Label each room with its name:
    LIVING ROOM, KITCHEN, BEDROOM 1, BATHROOM, BEDROOM 2

---------------------------------------------
OUTPUT
---------------------------------------------
  Save as: /home/ga/Documents/LibreCAD/apartment_plan.dxf

=============================================
EOF

chmod 644 "$DOCS_DIR/apartment_brief.txt"
chown -R ga:ga "$DOCS_DIR"

echo "Architectural brief created at $DOCS_DIR/apartment_brief.txt"

# 5. Start LibreCAD with a blank drawing
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad_task.log 2>&1 &"
sleep 8

# 6. Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "librecad"; then
        echo "LibreCAD window detected."
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# 7. Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 1

# 8. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="
