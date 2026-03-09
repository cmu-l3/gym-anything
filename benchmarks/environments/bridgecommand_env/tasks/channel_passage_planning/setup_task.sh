#!/bin/bash
echo "=== Setting up channel_passage_planning task ==="

BC_BIN="/opt/bridgecommand/bridgecommand"
BC_DATA="/opt/bridgecommand"
BC_CONFIG="/home/ga/.config/Bridge Command/bc5.ini"
SCENARIO_DIR="$BC_DATA/Scenarios/o) Dover Channel Transit"

if [ ! -x "$BC_BIN" ]; then
    echo "ERROR: Bridge Command binary not found"
    exit 1
fi

# Record baseline
INITIAL_SCENARIO_COUNT=$(ls -d "$BC_DATA/Scenarios/"*/ 2>/dev/null | wc -l)
echo "$INITIAL_SCENARIO_COUNT" > /tmp/initial_scenario_count

# Record baseline radar config
BASELINE_FULL_RADAR=$(grep -oP 'full_radar=\K[0-9]+' "$BC_CONFIG" 2>/dev/null || echo "0")
BASELINE_MAX_RANGE=$(grep -oP 'max_radar_range=\K[0-9]+' "$BC_CONFIG" 2>/dev/null || echo "48")
BASELINE_ANGULAR_RES=$(grep -oP 'radar_angular_resolution=\K[0-9]+' "$BC_CONFIG" 2>/dev/null || echo "360")
BASELINE_HIDE_INST=$(grep -oP 'hide_instruments=\K[0-9]+' "$BC_CONFIG" 2>/dev/null || echo "0")

cat > /tmp/initial_passage_state.json << EOF
{
    "task": "channel_passage_planning",
    "initial_scenario_count": $INITIAL_SCENARIO_COUNT,
    "baseline_full_radar": $BASELINE_FULL_RADAR,
    "baseline_max_radar_range": $BASELINE_MAX_RANGE,
    "baseline_radar_angular_resolution": $BASELINE_ANGULAR_RES,
    "baseline_hide_instruments": $BASELINE_HIDE_INST,
    "timestamp": "$(date -Iseconds)"
}
EOF

date -Iseconds > /tmp/task_start_timestamp

# Ensure target scenario does NOT exist
rm -rf "$SCENARIO_DIR" 2>/dev/null || true

# Ensure passage plan does NOT exist
rm -f /home/ga/Documents/passage_plan.txt 2>/dev/null || true
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Reset bc5.ini to defaults
cp /workspace/config/bc5.ini "$BC_CONFIG"
cp /workspace/config/bc5.ini "$BC_DATA/bc5.ini" 2>/dev/null || true
mkdir -p "/home/ga/.Bridge Command/5.10"
cp /workspace/config/bc5.ini "/home/ga/.Bridge Command/5.10/bc5.ini" 2>/dev/null || true
chown -R ga:ga "/home/ga/.config/Bridge Command"
chown -R ga:ga "/home/ga/.Bridge Command" 2>/dev/null || true

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
