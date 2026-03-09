#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero

echo "=== Setting up glycolysis_metabolic_pathway task ==="

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
rm -f /home/ga/Desktop/glycolysis.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/glycolysis.png 2>/dev/null || true
rm -f /home/ga/Desktop/glycolysis_reactions.txt 2>/dev/null || true

# Create the reaction list text file
cat > /home/ga/Desktop/glycolysis_reactions.txt << 'TXTEOF'
GLYCOLYSIS: ENERGY INVESTMENT PHASE (STEPS 1-5)
===============================================

Step 1: Phosphorylation
   Input: Glucose
   Cofactors: ATP -> ADP
   Enzyme: Hexokinase
   Output: Glucose-6-Phosphate

Step 2: Isomerization
   Input: Glucose-6-Phosphate
   Enzyme: Phosphoglucose Isomerase
   Output: Fructose-6-Phosphate

Step 3: Phosphorylation
   Input: Fructose-6-Phosphate
   Cofactors: ATP -> ADP
   Enzyme: Phosphofructokinase
   Output: Fructose-1,6-Bisphosphate

Step 4: Cleavage (The Split)
   Input: Fructose-1,6-Bisphosphate
   Enzyme: Aldolase
   Output 1: Dihydroxyacetone Phosphate
   Output 2: Glyceraldehyde-3-Phosphate

Step 5: Isomerization
   Input: Dihydroxyacetone Phosphate
   Enzyme: Triose Phosphate Isomerase
   Output: Glyceraldehyde-3-Phosphate
TXTEOF

chown ga:ga /home/ga/Desktop/glycolysis_reactions.txt
chmod 644 /home/ga/Desktop/glycolysis_reactions.txt

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Launch draw.io (blank)
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

# Dismiss startup dialog (Esc creates blank diagram)
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="