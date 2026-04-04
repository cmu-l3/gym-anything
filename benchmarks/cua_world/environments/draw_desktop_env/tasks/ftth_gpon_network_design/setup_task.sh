#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero

echo "=== Setting up FTTH GPON Network Design task ==="

# 1. Create the specifications file with ground truth data for the agent
cat > /home/ga/Desktop/gpon_specs.txt << 'EOF'
FTTH GPON NETWORK DESIGN SPECIFICATIONS
=======================================

PROJECT: Sunset Valley Subdivision Phase 1
TOPOLOGY: Tree (Point-to-Multipoint)

OPTICAL PARAMETERS (Link Budget):
---------------------------------
- OLT Transmit Power (Tx):        +3.00 dBm
- Fiber Cable Loss (1310/1490nm): 0.35 dB/km
- 1:4 Splitter Insertion Loss:    7.20 dB
- 1:8 Splitter Insertion Loss:    10.50 dB
- Connector/Splice Losses:        Included in component margins

NETWORK TOPOLOGY & DISTANCES:
-----------------------------
1. FEEDER SEGMENT:
   - Central Office (OLT) --> Street Cabinet (Primary Splitter 1:4)
   - Distance: 12.0 km

2. DISTRIBUTION SEGMENT:
   - The Primary Splitter feeds multiple distribution lines.
   - We are designing for Distribution Line 1 which goes to a Manhole (Secondary Splitter 1:8).

   Distances from Primary Splitter to Secondary Splitters:
   - To Cluster A (House A): 2.0 km
   - To Cluster B (House B): 4.5 km
   - To Cluster C (House C): 0.5 km

3. DROP SEGMENT:
   - From Secondary Splitter to Customer Premises (ONT).
   
   Drop Cable Distances:
   - House A: 0.2 km
   - House B: 0.1 km
   - House C: 0.05 km

TASK INSTRUCTIONS:
------------------
1. Draw the network diagram in draw.io.
   Structure: OLT -> Feeder Fiber -> 1:4 Splitter -> Distribution Fiber -> 1:8 Splitter -> Drop Cable -> House/ONT
   
   Note: Since House A, B, and C are at different distances, draw them as separate branches originating from the 1:4 splitter level (conceptually), or explicitly show the distribution fiber lengths. The key is to model the path correctly for calculation.

2. Label all fiber segments with their lengths (km).

3. CALCULATE the received signal level (dBm) at each House (A, B, C).
   Formula: Rx = Tx - (Total Fiber Length * 0.35) - Sum(Splitter Losses)
   
4. Add a text label next to each House shape with the result (e.g., "Rx: -18.5 dBm").

5. Export as PDF to ~/Desktop/ftth_design.pdf.
EOF

chown ga:ga /home/ga/Desktop/gpon_specs.txt
chmod 644 /home/ga/Desktop/gpon_specs.txt

# 2. Record start time and initial state
date +%s > /tmp/task_start_timestamp

# Check if draw.io binary exists
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

# 3. Launch draw.io (Blank Canvas)
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_gpon.log 2>&1 &"

# Wait for window
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Wait for UI load
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss startup dialog (creates blank diagram)
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="