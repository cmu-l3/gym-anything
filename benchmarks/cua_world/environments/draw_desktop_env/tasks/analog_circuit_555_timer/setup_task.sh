#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero

echo "=== Setting up analog_circuit_555_timer task ==="

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
rm -f /home/ga/Desktop/555_schematic.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/555_schematic.png 2>/dev/null || true

# Create the Netlist file
cat > /home/ga/Desktop/555_netlist.txt << 'EOF'
CIRCUIT: 555 Timer Astable Multivibrator (Blinking LED)

COMPONENTS:
- U1: 555 Timer IC (8 pins)
- R1: 1k Ohm Resistor
- R2: 470k Ohm Resistor
- R3: 220 Ohm Resistor
- C1: 1uF Capacitor
- D1: LED (Light Emitting Diode)
- Power: +9V (VCC) and Ground (GND)

CONNECTIONS:
1. Connect U1 Pin 1 (GND) to Ground.
2. Connect U1 Pin 8 (VCC) and Pin 4 (RESET) to +9V.
3. Place Resistor R1 between +9V and U1 Pin 7 (DISCHARGE).
4. Place Resistor R2 between U1 Pin 7 (DISCHARGE) and U1 Pin 6 (THRESHOLD).
5. Connect U1 Pin 2 (TRIGGER) directly to U1 Pin 6 (THRESHOLD).
   (Note: Pins 2 and 6 should be tied together).
6. Place Capacitor C1 between U1 Pin 2 and Ground.
7. Connect U1 Pin 3 (OUTPUT) to one end of Resistor R3.
8. Connect the other end of R3 to the Anode (+) of LED D1.
9. Connect the Cathode (-) of LED D1 to Ground.

LABELS:
Please label all components with their Name (e.g., R1) and Value (e.g., 1k).
EOF

chown ga:ga /home/ga/Desktop/555_netlist.txt
chmod 644 /home/ga/Desktop/555_netlist.txt

# Record start timestamp
date +%s > /tmp/task_start_time.txt

# Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_launch.log 2>&1 &"

# Wait for window
echo "Waiting for draw.io window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "Window found."
        break
    fi
    sleep 1
done
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss startup dialog to create blank diagram
# Pressing Escape usually closes the "Open/Create" dialog and leaves a blank canvas or standard UI
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape
sleep 2

# Verify application is focused
DISPLAY=:1 wmctrl -a "draw.io" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="