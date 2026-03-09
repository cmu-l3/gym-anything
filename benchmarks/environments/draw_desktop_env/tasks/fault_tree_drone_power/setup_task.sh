#!/bin/bash
set -u

echo "=== Setting up fault_tree_drone_power task ==="

# 1. Create the System Specification File
# This uses realistic safety engineering terminology
cat > /home/ga/Desktop/drone_system_spec.txt << 'EOF'
SYSTEM SAFETY SPECIFICATION: DRONE-X1 POWER ARCHITECTURE
DOC ID: SAF-2024-001
DATE: 2024-10-15

1. SYSTEM OVERVIEW
The Drone-X1 utilizes a redundant power architecture designed to maintain flight capability in the event of a single battery failure.

2. COMPONENT DESCRIPTION
- Main Power Distribution Board (PDB): Receives power from sources and distributes it to the 4 motor ESCs.
- Battery A: Primary 6S LiPo battery pack.
- Battery B: Secondary 6S LiPo battery pack.

3. FUNCTIONAL LOGIC (POSITIVE)
- The PDB contains an active diode OR-ing circuit.
- The drone remains powered if (Battery A provides voltage) OR (Battery B provides voltage).

4. FAILURE LOGIC (NEGATIVE - FOR FAULT TREE)
- Top Event: "Total Loss of Power" (Motors stop spinning).
- The PDB itself is a single point of failure. If the PDB circuitry fails, power is lost immediately.
- Power is also lost if the Battery System fails to provide voltage.
- Due to the OR-ing circuit, the Battery System only fails if BOTH Battery A fails AND Battery B fails simultaneously.

5. BATTERY FAILURE MODES
Each battery pack is considered failed if ANY of the following occur:
- Internal Cell Malfunction (Short/Open circuit)
- Connector Disconnect (XT90 connector vibrates loose)

6. TASK INSTRUCTIONS
Create a Fault Tree Analysis (FTA) diagram.
- Top Event: Total Loss of Power
- Break down into intermediate events and basic events.
- Use Boolean Logic Gates (AND, OR) to represent the relationships described above.
- Use Circles for Basic Events (root causes like "Cell Malfunction").
EOF

chown ga:ga /home/ga/Desktop/drone_system_spec.txt
chmod 644 /home/ga/Desktop/drone_system_spec.txt

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Launch draw.io
# Find binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then DRAWIO_BIN="drawio";
elif [ -f /opt/drawio/drawio ]; then DRAWIO_BIN="/opt/drawio/drawio";
elif [ -f /usr/bin/drawio ]; then DRAWIO_BIN="/usr/bin/drawio"; fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found"
    exit 1
fi

echo "Launching draw.io..."
# Launch with update disabled
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_launch.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss startup dialog (Esc creates blank diagram)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="