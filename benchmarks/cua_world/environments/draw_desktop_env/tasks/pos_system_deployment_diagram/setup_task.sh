#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero

echo "=== Setting up pos_system_deployment_diagram task ==="

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
rm -f /home/ga/Desktop/pos_deployment.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/pos_deployment.png 2>/dev/null || true

# Create the Technical Specification file
cat > /home/ga/Desktop/pos_technical_specs.txt << 'SPECEOF'
PROJECT: Store 2.0 Checkout Lane Configuration
DATE: 2024-05-15

HARDWARE CONFIGURATION:
1. Checkout Terminal (Node)
   - Role: Main register PC
   - OS: Windows 10 IoT
   - Hostname: POS-LANE-01

2. Store Controller (Node)
   - Role: Back office server
   - Hostname: SRV-STORE-01

3. Peripherals (Devices connected to Checkout Terminal):
   - Barcode Scanner (Handheld) -> Connected via USB
   - Receipt Printer (Thermal) -> Connected via RS-232 (COM1)
   - Payment Pin Pad (Verifone) -> Connected via Ethernet (Networked)

SOFTWARE DEPLOYMENT:
1. On Checkout Terminal:
   - Component: "POS Client App.exe"
   - Component: "OPOS Drivers"

2. On Store Controller:
   - Component: "Transaction Service"
   - Component: "SQL Express DB"

NETWORK CONNECTIONS:
- The Checkout Terminal connects to the Store Controller via LAN (TCP/IP) on port 1433/8080.
SPECEOF

chown ga:ga /home/ga/Desktop/pos_technical_specs.txt
echo "Created technical specs at /home/ga/Desktop/pos_technical_specs.txt"

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_pos.log 2>&1 &"

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

# Dismiss "Create New/Open Existing" dialog to start with blank canvas
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape
sleep 2

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/pos_task_start.png 2>/dev/null || true

echo "=== Task setup complete ==="