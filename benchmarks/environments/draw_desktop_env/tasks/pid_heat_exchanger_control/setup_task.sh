#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero

echo "=== Setting up pid_heat_exchanger_control task ==="

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

# Clean up any existing output files
rm -f /home/ga/Desktop/heat_exchanger_pid.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/heat_exchanger_pid.png 2>/dev/null || true

# Create the specifications file
cat > /home/ga/Desktop/pid_specs.txt << 'EOF'
PROJECT: UNIT 200 UPGRADE
SYSTEM: PROCESS WATER HEATER
DATE: 2025-05-20

Construct a P&ID for the following loop:

1. EQUIPMENT
   - Main Unit: Shell & Tube Heat Exchanger
   - Tag: HX-200

2. STREAMS
   - Process Fluid (Tube Side): Enters as "Cold Water", Exits as "Hot Water".
   - Utility Fluid (Shell Side): Enters as "LP Steam", Exits as "Condensate".

3. INSTRUMENTATION & CONTROL
   - Loop ID: 201
   - Primary Variable: Temperature of Hot Water outlet.
   - Sensor: Temperature Transmitter (Tag: TT-201). Mounted on outlet pipe.
   - Controller: Temperature Indicator Controller (Tag: TIC-201). Located in Main Control Room (Shared Display).
   - Final Element: Globe Control Valve (Tag: TV-201) with Diaphragm Actuator. Located on Steam Inlet line.
   - Action: Feedback control. TIC-201 receives signal from TT-201 and adjusts TV-201 to maintain setpoint.
EOF

chown ga:ga /home/ga/Desktop/pid_specs.txt
chmod 644 /home/ga/Desktop/pid_specs.txt

# Record start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Launch draw.io (startup dialog will appear)
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_pid.log 2>&1 &"

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

# Maximize the window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss startup dialog (Press Escape to create blank diagram)
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape
sleep 2

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/pid_task_start.png 2>/dev/null || true

echo "=== pid_heat_exchanger_control task setup completed ==="