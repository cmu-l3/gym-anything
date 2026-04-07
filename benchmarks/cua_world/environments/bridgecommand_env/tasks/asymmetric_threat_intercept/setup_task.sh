#!/bin/bash
echo "=== Setting up Asymmetric Threat Intercept Task ==="

BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/n) Swarm Attack Drill"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure Bridge Command directory structure exists
if [ ! -d "$BC_DATA/Scenarios" ]; then
    echo "ERROR: Scenarios directory not found at $BC_DATA/Scenarios"
    exit 1
fi

# Clean up previous attempts (Start Fresh)
if [ -d "$SCENARIO_DIR" ]; then
    echo "Removing existing scenario directory..."
    rm -rf "$SCENARIO_DIR"
fi

# Remove previous calculation documents
rm -f /home/ga/Documents/intercept_calculations.txt

# Create necessary directories
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Ensure bc5.ini is clean (reset to default)
BC_CONFIG_DIR="/home/ga/.config/Bridge Command"
mkdir -p "$BC_CONFIG_DIR"
cp /workspace/config/bc5.ini "$BC_CONFIG_DIR/bc5.ini"
chown -R ga:ga "$BC_CONFIG_DIR"

# Launch Bridge Command (Warm-up / ensure available)
# We don't need it running for the calculation part, but the agent might use it to test.
# We'll just leave it closed so the agent can open it if they wish, or work in terminal.
# Just ensure the binary is executable.
chmod +x "$BC_DATA/bridgecommand"

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Task ready. Create scenario at: $SCENARIO_DIR"