#!/bin/bash
echo "=== Setting up Emergency Wreck Marking Task ==="

SCENARIO_DIR="/opt/bridgecommand/Scenarios/z) Wreck of MV Meridian"

# 1. Clean up previous run artifacts to ensure a fresh start
if [ -d "$SCENARIO_DIR" ]; then
    echo "Removing existing scenario directory..."
    rm -rf "$SCENARIO_DIR"
fi

# 2. Record start time for anti-gaming (file creation check)
date +%s > /tmp/task_start_time.txt

# 3. Ensure Bridge Command isn't running
pkill -f "bridgecommand" 2>/dev/null || true

# 4. Record initial state of scenarios directory
ls -R /opt/bridgecommand/Scenarios > /tmp/initial_scenarios_list.txt

echo "=== Setup Complete ==="
echo "Target Datum: 50.7000 N, 001.3000 W"
echo "Required Offset: 0.5 Nautical Miles"