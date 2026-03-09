#!/bin/bash
echo "=== Setting up select_and_start_scenario task ==="

BC_BIN="/opt/bridgecommand/bridgecommand"
BC_DATA="/opt/bridgecommand"

if [ ! -x "$BC_BIN" ]; then
    echo "ERROR: Bridge Command binary not found at $BC_BIN"
    exit 1
fi

# Record initial state
cat > /tmp/initial_state.json << EOF
{
    "task": "select_and_start_scenario",
    "target_scenario": "i) Portsmouth Night Entry",
    "bc_binary": "$BC_BIN",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Kill any existing Bridge Command instance
pkill -f "bridgecommand" 2>/dev/null || true
sleep 2

# Launch Bridge Command from its data directory (required for BC to find assets)
echo "Starting Bridge Command..."
su - ga -c "cd $BC_DATA && DISPLAY=:1 ./bridgecommand > /tmp/bc_task.log 2>&1 &"
sleep 8

# Check if Bridge Command started
BC_PID=$(pgrep -f "$BC_BIN" 2>/dev/null | head -1)
if [ -n "$BC_PID" ]; then
    echo "Bridge Command is running (PID $BC_PID)"
else
    echo "WARNING: Bridge Command may not have started"
    cat /tmp/bc_task.log 2>/dev/null || true
fi

# Try to focus the Bridge Command window
DISPLAY=:1 wmctrl -a "Bridge Command" 2>/dev/null || true
sleep 1

# Take initial screenshot
su - ga -c "DISPLAY=:1 scrot /tmp/task_start.png" 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Task: Select 'i) Portsmouth Night Entry' scenario, click OK, and start the simulation"
echo "The Bridge Command launcher is open. Click 'Start Bridge Command' to see scenario selection."
