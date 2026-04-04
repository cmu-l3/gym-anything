#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero

echo "=== Setting up retail_shelf_planogram task ==="

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

# Clean up previous runs
rm -f /home/ga/Desktop/cereal_planogram.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/cereal_planogram.png 2>/dev/null || true

# Create Merchandising Strategy File
cat > /home/ga/Desktop/merchandising_strategy.txt << 'TXTEOF'
MERCHANDISING STRATEGY: BREAKFAST CEREAL (BAY 1)
================================================

FIXTURE SPECIFICATIONS:
- Type: Standard Gondola Bay
- Width: 48 inches
- Height: 72 inches
- Shelves: 4 adjustable shelves
    * Shelf 4 (Top):    60" - 72" height
    * Shelf 3 (Eye):    44" - 60" height
    * Shelf 2 (Touch):  24" - 44" height
    * Shelf 1 (Bottom): 06" - 24" height

PRODUCT LIST & DIMENSIONS (Width x Height):
-------------------------------------------
1. All Bran         (8" x 12")
2. Muesli           (8" x 11")
3. Corn Flakes      (10" x 14")
4. Raisin Bran      (9" x 14")
5. Froot Loops      (9" x 13")
6. Apple Jacks      (9" x 13")
7. Bag O' Puffs     (14" x 18")
8. Value Oats       (12" x 16")

PLACEMENT STRATEGY RULES:
-------------------------
1. ADULT / HEALTHY -> TOP SHELF (Shelf 4)
   - Products: All Bran, Muesli
   - Logic: Intentional purchase, customers will reach up for these.

2. BEST SELLERS -> EYE LEVEL (Shelf 3)
   - Products: Corn Flakes, Raisin Bran
   - Logic: Prime real estate for highest margin volume drivers.

3. KIDS / SUGAR -> TOUCH LEVEL (Shelf 2)
   - Products: Froot Loops, Apple Jacks
   - Logic: Eye level for children, easy reach for parents.

4. BULK / VALUE -> BOTTOM SHELF (Shelf 1)
   - Products: Bag O' Puffs, Value Oats
   - Logic: Large, heavy items go on bottom for safety and stability.

INSTRUCTIONS:
Create a planogram diagram showing these products arranged on the fixture.
Ensure products are placed on their correct assigned shelf levels.
TXTEOF

chown ga:ga /home/ga/Desktop/merchandising_strategy.txt
chmod 644 /home/ga/Desktop/merchandising_strategy.txt

# Record start time
date +%s > /tmp/task_start_timestamp

# Launch draw.io (startup dialog will appear)
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_planogram.log 2>&1 &"

# Wait for window
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected after ${i} seconds"
        break
    fi
    sleep 1
done

sleep 5

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss startup dialog (Esc creates blank diagram)
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape
sleep 2

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/planogram_start.png 2>/dev/null || true

echo "=== Setup complete ==="