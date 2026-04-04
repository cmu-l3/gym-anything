#!/bin/bash
echo "=== Setting up instrument_failure_diagnosis task ==="

BC_BIN="/opt/bridgecommand/bridgecommand"
BC_DATA="/opt/bridgecommand"
BC_CONFIG="/home/ga/.config/Bridge Command/bc5.ini"
SCENARIO_DIR="$BC_DATA/Scenarios/m) Portsmouth Approach Custom"

if [ ! -x "$BC_BIN" ]; then
    echo "ERROR: Bridge Command binary not found"
    exit 1
fi

# Ensure scenario directory exists (it should have been installed by setup_bridgecommand.sh)
if [ ! -d "$SCENARIO_DIR" ]; then
    echo "Custom scenario not found, creating from workspace data..."
    if [ -d /workspace/data/portsmouth_approach ]; then
        cp -r /workspace/data/portsmouth_approach "$SCENARIO_DIR"
    else
        echo "ERROR: Neither scenario nor source data found"
        exit 1
    fi
fi

# Record correct baseline values BEFORE injecting faults
CORRECT_VIEW_ANGLE=90
CORRECT_RADAR_RES=128
CORRECT_MAX_RANGE=48
CORRECT_VISIBILITY=10.0
CORRECT_SPEED=8.0
CORRECT_VESSEL_COUNT=2

# Save baseline
cat > /tmp/initial_instrument_state.json << EOF
{
    "task": "instrument_failure_diagnosis",
    "correct_values": {
        "view_angle": $CORRECT_VIEW_ANGLE,
        "radar_range_resolution": $CORRECT_RADAR_RES,
        "max_radar_range": $CORRECT_MAX_RANGE,
        "visibility_range": $CORRECT_VISIBILITY,
        "initial_speed": $CORRECT_SPEED,
        "vessel_count": $CORRECT_VESSEL_COUNT
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

date -Iseconds > /tmp/task_start_timestamp

# === INJECT FAULTS ===

# Fault 1: bc5.ini — view_angle set to 5 (nearly zero FOV, unusable)
cp /workspace/config/bc5.ini "$BC_CONFIG"
sed -i 's/^view_angle=.*/view_angle=5/' "$BC_CONFIG"

# Fault 2: bc5.ini — radar_range_resolution set to 8 (extremely low)
sed -i 's/^radar_range_resolution=.*/radar_range_resolution=8/' "$BC_CONFIG"

# Fault 3: bc5.ini — max_radar_range set to 2 (only 2nm, nearly useless)
sed -i 's/^max_radar_range=.*/max_radar_range=2/' "$BC_CONFIG"

# Copy corrupted config to all locations BC reads from
cp "$BC_CONFIG" "$BC_DATA/bc5.ini" 2>/dev/null || true
mkdir -p "/home/ga/.Bridge Command/5.10"
cp "$BC_CONFIG" "/home/ga/.Bridge Command/5.10/bc5.ini" 2>/dev/null || true

chown -R ga:ga "/home/ga/.config/Bridge Command"
chown -R ga:ga "/home/ga/.Bridge Command" 2>/dev/null || true

# Fault 4: environment.ini — VisibilityRange set to 0.1 (dense fog)
sed -i 's/^VisibilityRange=.*/VisibilityRange=0.1/' "$SCENARIO_DIR/environment.ini"

# Fault 5: ownship.ini — InitialSpeed set to 85.0 (absurdly high for a ship)
sed -i 's/^InitialSpeed=.*/InitialSpeed=85.0/' "$SCENARIO_DIR/ownship.ini"

# Fault 6: othership.ini — Number set to 0 (all traffic removed)
# Save backup of original othership data, then zero out the count
cp "$SCENARIO_DIR/othership.ini" "$SCENARIO_DIR/.othership_backup"
sed -i 's/^Number=.*/Number=0/' "$SCENARIO_DIR/othership.ini"

# Create the vessel specs reference document
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/vessel_specs.txt << 'SPECS'
MV SENTINEL - BRIDGE INSTRUMENT SPECIFICATIONS
================================================

Normal Operating Parameters (per manufacturer calibration):

DISPLAY & OPTICS
  Field of View (view_angle): 90 degrees
  Look Angle: 0 degrees (level horizon)
  Min Display Distance: 0.05 nm
  Max Display Distance: 100000 nm

RADAR SYSTEM
  Range Resolution: 128 cells
  Angular Resolution: 360 sectors
  Maximum Radar Range: 48 nm
  ARPA: Disabled by default (enable for COLREGS exercises)
  Full Radar Display: Disabled by default

NAVIGATION
  GPS: Enabled (4 decimal precision)
  Depth Sounder: Enabled
  Compass Deviation: None applied

SCENARIO: Portsmouth Approach Custom
  Normal visibility: 10.0 nm
  Normal approach speed: 8.0 knots
  Expected traffic: 2 vessels (1 tanker, 1 yacht)
  Weather: 3.0 (moderate)

Last calibration: 2024-06-15
Approved by: Chief Electronics Officer, Port of Southampton
SPECS

chown ga:ga /home/ga/Documents/vessel_specs.txt

# Ensure fault report does NOT exist
rm -f /home/ga/Documents/fault_report.txt

# Kill any existing BC instance and relaunch with corrupted config
pkill -f "bridgecommand" 2>/dev/null || true
sleep 2

echo "Starting Bridge Command with corrupted configuration..."
su - ga -c "cd $BC_DATA && DISPLAY=:1 ./bridgecommand > /tmp/bc_task.log 2>&1 &"
sleep 8

BC_PID=$(pgrep -f "$BC_BIN" 2>/dev/null | head -1)
if [ -n "$BC_PID" ]; then
    echo "Bridge Command is running (PID $BC_PID)"
else
    echo "WARNING: Bridge Command may not have started"
fi

DISPLAY=:1 wmctrl -a "Bridge Command" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 scrot /tmp/task_start.png" 2>/dev/null || true

echo "=== Setup Complete ==="
echo "6 faults have been injected. Vessel specs available at /home/ga/Documents/vessel_specs.txt"
