#!/bin/bash
set -euo pipefail

echo "=== Setting up Sheet Metal Flat Pattern Task ==="

# 1. Clean up and prepare directories
pkill -f librecad 2>/dev/null || true
sleep 2

DOCS_DIR="/home/ga/Documents/LibreCAD"
mkdir -p "$DOCS_DIR"
rm -f "$DOCS_DIR/chassis_flat_pattern.dxf"
rm -f "$DOCS_DIR/work_order_001.txt"

# 2. Generate Work Order File
cat > "$DOCS_DIR/work_order_001.txt" << EOF
WORK ORDER: WO-001
PART: Electronics Chassis Tray
DATE: $(date +%F)

DESCRIPTION:
Create a flat pattern DXF for laser cutting.
The part is a rectangular tray with folded up sides (flanges).

DIMENSIONS (mm):
- Base Size: 120mm (Width) x 80mm (Depth)
- Flange Height: 25mm (All 4 sides)
- Corner Relief: Open Square (flanges do not overlap)

HOLE SPECIFICATIONS:
- Quantity: 4
- Diameter: 6mm
- Location: Inside the base area, offset 15mm from the bend lines at each corner.

LAYER REQUIREMENTS (Strict):
1. Layer Name: CUT_EXTERIOR
   - Color: White (Index 7)
   - Usage: Outer profile of the flat part (Base + Flanges)

2. Layer Name: BEND_LINES
   - Color: Yellow (Index 2)
   - Line Type: DASHED (Must not be Continuous)
   - Usage: The rectangle where the base meets the flanges

3. Layer Name: CUT_HOLES
   - Color: Red (Index 1)
   - Usage: Mounting holes
EOF

chmod 644 "$DOCS_DIR/work_order_001.txt"
chown -R ga:ga "$DOCS_DIR"

echo "Work order created at $DOCS_DIR/work_order_001.txt"

# 3. Start LibreCAD
# We start with a blank drawing.
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad_task.log 2>&1 &"
sleep 6

# 4. Configure Window
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# 5. Record start time and initial state
date +%s > /tmp/task_start_time.txt
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="