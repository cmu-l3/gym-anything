#!/bin/bash
set -e
echo "=== Setting up Fastnet '79 Reconstruction Task ==="

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Define Scenario Path
SCENARIO_PATH="/opt/bridgecommand/Scenarios/z) Fastnet 1979 Reconstruction"

# 3. Clean State: Remove the scenario if it already exists (from previous runs)
if [ -d "$SCENARIO_PATH" ]; then
    echo "Removing existing scenario artifact..."
    rm -rf "$SCENARIO_PATH"
fi

# 4. Ensure Bridge Command is ready (though we mostly edit files, agent might check models)
BC_BIN="/opt/bridgecommand/bridgecommand"
if [ ! -x "$BC_BIN" ]; then
    echo "ERROR: Bridge Command binary not found."
    exit 1
fi

# 5. Open a file explorer or terminal to hint where to start
# We'll open the Scenarios folder in a file manager if available, or just a terminal
if command -v nautilus >/dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 nautilus /opt/bridgecommand/Scenarios &"
elif command -v thunar >/dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 thunar /opt/bridgecommand/Scenarios &"
else
    # Fallback to terminal
    su - ga -c "DISPLAY=:1 x-terminal-emulator &"
fi

# 6. Capture initial state
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="