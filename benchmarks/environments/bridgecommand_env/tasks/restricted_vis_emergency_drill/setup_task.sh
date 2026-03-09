#!/bin/bash
echo "=== Setting up restricted_vis_emergency_drill task ==="

BC_BIN="/opt/bridgecommand/bridgecommand"
BC_DATA="/opt/bridgecommand"
BC_CONFIG="/home/ga/.config/Bridge Command/bc5.ini"
SCENARIO_DIR="$BC_DATA/Scenarios/m) Portsmouth Approach Custom"

if [ ! -x "$BC_BIN" ]; then
    echo "ERROR: Bridge Command binary not found"
    exit 1
fi

# Ensure custom scenario exists with ORIGINAL data
if [ -d /workspace/data/portsmouth_approach ]; then
    rm -rf "$SCENARIO_DIR" 2>/dev/null || true
    cp -r /workspace/data/portsmouth_approach "$SCENARIO_DIR"
    echo "Restored original Portsmouth Approach scenario"
else
    echo "ERROR: Source scenario data not found"
    exit 1
fi

# Record baseline values from ORIGINAL scenario
BASELINE_VIS=$(grep -oP 'VisibilityRange=\K[0-9.]+' "$SCENARIO_DIR/environment.ini" 2>/dev/null || echo "10.0")
BASELINE_WEATHER=$(grep -oP 'Weather=\K[0-9.]+' "$SCENARIO_DIR/environment.ini" 2>/dev/null || echo "3.0")
BASELINE_SPEED=$(grep -oP 'InitialSpeed=\K[0-9.]+' "$SCENARIO_DIR/ownship.ini" 2>/dev/null || echo "8.0")
BASELINE_SHIP_NAME=$(grep -oP 'ShipName="\K[^"]+' "$SCENARIO_DIR/ownship.ini" 2>/dev/null || echo "MV Sentinel")
BASELINE_VESSEL_COUNT=$(grep -oP 'Number=\K[0-9]+' "$SCENARIO_DIR/othership.ini" 2>/dev/null || echo "2")
BASELINE_V1_SPEED=$(grep -oP 'Speed\(1,1\)=\K[0-9]+' "$SCENARIO_DIR/othership.ini" 2>/dev/null || echo "8")
BASELINE_V2_SPEED=$(grep -oP 'Speed\(2,1\)=\K[0-9]+' "$SCENARIO_DIR/othership.ini" 2>/dev/null || echo "5")

cat > /tmp/initial_fogdrill_state.json << EOF
{
    "task": "restricted_vis_emergency_drill",
    "baseline": {
        "visibility": $BASELINE_VIS,
        "weather": $BASELINE_WEATHER,
        "own_speed": $BASELINE_SPEED,
        "ship_name": "$BASELINE_SHIP_NAME",
        "vessel_count": $BASELINE_VESSEL_COUNT,
        "v1_speed": $BASELINE_V1_SPEED,
        "v2_speed": $BASELINE_V2_SPEED
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

date -Iseconds > /tmp/task_start_timestamp

# Reset bc5.ini to defaults (arpa_on=0, full_radar=0)
cp /workspace/config/bc5.ini "$BC_CONFIG"
cp /workspace/config/bc5.ini "$BC_DATA/bc5.ini" 2>/dev/null || true
mkdir -p "/home/ga/.Bridge Command/5.10"
cp /workspace/config/bc5.ini "/home/ga/.Bridge Command/5.10/bc5.ini" 2>/dev/null || true
chown -R ga:ga "/home/ga/.config/Bridge Command"
chown -R ga:ga "/home/ga/.Bridge Command" 2>/dev/null || true

# Ensure checklist does NOT exist
rm -f /home/ga/Documents/fog_drill_checklist.txt 2>/dev/null || true
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Kill existing BC and relaunch
pkill -f "bridgecommand" 2>/dev/null || true
sleep 2

echo "Starting Bridge Command..."
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
echo "Original Portsmouth Approach scenario loaded. Modify it for fog drill exercise."
