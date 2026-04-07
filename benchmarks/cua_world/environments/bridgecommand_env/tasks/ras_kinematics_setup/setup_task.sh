#!/bin/bash
echo "=== Setting up RAS Kinematics Task ==="

# Define paths
SCENARIO_DIR="/opt/bridgecommand/Scenarios/n) RAS Exercise"
DOCS_DIR="/home/ga/Documents"

# 1. Clean up any previous attempts (Anti-gaming: clean slate)
if [ -d "$SCENARIO_DIR" ]; then
    echo "Removing existing scenario directory..."
    rm -rf "$SCENARIO_DIR"
fi
rm -f "$DOCS_DIR/ras_calc.txt"

# 2. Record task start time for timestamp verification
date +%s > /tmp/task_start_time.txt

# 3. Ensure Bridge Command is ready (though this is primarily a file task, the agent might use the editor)
# We won't launch the full sim as it grabs the mouse, but we ensure the environment is ready.
mkdir -p "$DOCS_DIR"
chown ga:ga "$DOCS_DIR"

# 4. Take initial screenshot of the desktop/files
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="
echo "Task ready: Create RAS scenario in $SCENARIO_DIR"