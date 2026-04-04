#!/bin/bash
echo "=== Setting up nighttime_colregs_assessment task ==="

BC_BIN="/opt/bridgecommand/bridgecommand"
BC_DATA="/opt/bridgecommand"

if [ ! -x "$BC_BIN" ]; then
    echo "ERROR: Bridge Command binary not found at $BC_BIN"
    exit 1
fi

# Ensure the Scenarios directory exists
if [ ! -d "$BC_DATA/Scenarios" ]; then
    echo "ERROR: Scenarios directory not found at $BC_DATA/Scenarios"
    exit 1
fi

# Record baseline: count existing scenarios and capture radar config
INITIAL_SCENARIO_COUNT=$(ls -d "$BC_DATA/Scenarios/"*/ 2>/dev/null | wc -l)
echo "$INITIAL_SCENARIO_COUNT" > /tmp/initial_scenario_count

# Record baseline radar config values from bc5.ini
BC_CONFIG="/home/ga/.config/Bridge Command/bc5.ini"
BASELINE_ARPA=$(grep -oP 'arpa_on=\K[0-9]+' "$BC_CONFIG" 2>/dev/null || echo "0")
BASELINE_FULL_RADAR=$(grep -oP 'full_radar=\K[0-9]+' "$BC_CONFIG" 2>/dev/null || echo "0")
BASELINE_RADAR_RES=$(grep -oP 'radar_range_resolution=\K[0-9]+' "$BC_CONFIG" 2>/dev/null || echo "128")
BASELINE_MAX_RANGE=$(grep -oP 'max_radar_range=\K[0-9]+' "$BC_CONFIG" 2>/dev/null || echo "48")

cat > /tmp/initial_colregs_state.json << EOF
{
    "task": "nighttime_colregs_assessment",
    "initial_scenario_count": $INITIAL_SCENARIO_COUNT,
    "baseline_arpa_on": $BASELINE_ARPA,
    "baseline_full_radar": $BASELINE_FULL_RADAR,
    "baseline_radar_range_resolution": $BASELINE_RADAR_RES,
    "baseline_max_radar_range": $BASELINE_MAX_RANGE,
    "target_scenario_dir": "$BC_DATA/Scenarios/n) Solent COLREGS Night Assessment",
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Baseline scenario count: $INITIAL_SCENARIO_COUNT"
echo "Baseline ARPA: $BASELINE_ARPA, Full Radar: $BASELINE_FULL_RADAR"

# Ensure target scenario does NOT exist yet (clean state)
rm -rf "$BC_DATA/Scenarios/n) Solent COLREGS Night Assessment" 2>/dev/null || true

# Ensure briefing file does NOT exist yet
rm -f /home/ga/Documents/colregs_assessment_briefing.txt 2>/dev/null || true
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Reset bc5.ini to template defaults (arpa_on=0, full_radar=0, etc.)
cp /workspace/config/bc5.ini "$BC_CONFIG"
cp /workspace/config/bc5.ini "$BC_DATA/bc5.ini" 2>/dev/null || true
chown ga:ga "$BC_CONFIG"

# Record task start timestamp
date -Iseconds > /tmp/task_start_timestamp

# Kill any existing Bridge Command instance
pkill -f "bridgecommand" 2>/dev/null || true
sleep 2

# Launch Bridge Command
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
