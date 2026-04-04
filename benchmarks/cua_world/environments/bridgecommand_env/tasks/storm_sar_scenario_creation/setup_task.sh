#!/bin/bash
echo "=== Setting up storm_sar_scenario_creation task ==="

BC_BIN="/opt/bridgecommand/bridgecommand"
BC_DATA="/opt/bridgecommand"
BC_CONFIG="/home/ga/.config/Bridge Command/bc5.ini"
SCENARIO_DIR="$BC_DATA/Scenarios/p) Lizard SAR Exercise Storm"

if [ ! -x "$BC_BIN" ]; then
    echo "ERROR: Bridge Command binary not found"
    exit 1
fi

# Record baseline
INITIAL_SCENARIO_COUNT=$(ls -d "$BC_DATA/Scenarios/"*/ 2>/dev/null | wc -l)
echo "$INITIAL_SCENARIO_COUNT" > /tmp/initial_scenario_count

cat > /tmp/initial_sar_state.json << EOF
{
    "task": "storm_sar_scenario_creation",
    "initial_scenario_count": $INITIAL_SCENARIO_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF

date -Iseconds > /tmp/task_start_timestamp

# Ensure target scenario does NOT exist
rm -rf "$SCENARIO_DIR" 2>/dev/null || true

# Ensure briefing file does NOT exist
rm -f /home/ga/Documents/sar_briefing.txt 2>/dev/null || true
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
