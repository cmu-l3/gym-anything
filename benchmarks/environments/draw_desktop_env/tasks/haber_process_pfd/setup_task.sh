#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero harmlessly

echo "=== Setting up haber_process_pfd task ==="

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

# Clean up previous artifacts
rm -f /home/ga/Desktop/haber_process.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/haber_process.png 2>/dev/null || true

# Create the Process Description file
cat > /home/ga/Desktop/process_description.txt << 'EOF'
PROCESS ENGINEERING REQUEST - AMMONIA SYNTHESIS LOOP (PFD-101)

Please generate a PFD for the high-pressure synthesis loop with the following specifications:

1. FEED: Fresh Nitrogen (N2) and Hydrogen (H2) gas enters the system.
2. COMPRESSION: Feed gas enters a Centrifugal Compressor to raise pressure to 200 bar.
3. HEATING: Compressed gas passes through a Pre-heater (Heat Exchanger) to reach reaction temperature.
4. REACTION: Hot gas enters the Catalytic Reactor (Iron catalyst bed). N2 + 3H2 -> 2NH3.
5. COOLING: Hot product gas passes through a Condenser/Cooler to liquefy the Ammonia.
6. SEPARATION: The stream enters a High-Pressure Separator (Vertical Vessel).
   - Bottoms: Liquid Ammonia (NH3) product is drawn off.
   - Tops: Unreacted N2 and H2 gas.
7. RECYCLE: The unreacted gas from the Separator top is piped back to the Compressor inlet (or mixed with feed) to improve yield.

REQUIREMENTS:
- Use standard Process Engineering symbols (from the "PID" or "Chemical" shape libraries).
- Label all main equipment and streams.
- Clearly show the recycle loop.
EOF

chown ga:ga /home/ga/Desktop/process_description.txt
chmod 644 /home/ga/Desktop/process_description.txt

# Record task start time
date +%s > /tmp/task_start_timestamp

# Launch draw.io
echo "Launching draw.io..."
# Use a launch helper if available, or direct command
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_pfd.log 2>&1 &"

# Wait for draw.io window
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected after ${i} seconds"
        break
    fi
    sleep 1
done

sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss the "Create New / Open Existing" dialog to start with a blank canvas
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape
sleep 2

# Verify running state
if pgrep -f "drawio" > /dev/null; then
    echo "draw.io is running"
else
    echo "WARNING: draw.io might not be running"
fi

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="