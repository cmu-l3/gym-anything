#!/bin/bash
echo "=== Setting up VLCC Model Calibration Task ==="

# Record task start time for anti-gaming (file timestamp verification)
date +%s > /tmp/task_start_time.txt

# Paths
MODEL_DIR="/opt/bridgecommand/Models/VLCC_Training"
SCENARIO_DIR="/opt/bridgecommand/Scenarios/n) VLCC Channel Approach"
REPORT_FILE="/home/ga/Documents/vlcc_config_report.txt"

# Clean up previous run artifacts to ensure clean state
if [ -d "$MODEL_DIR" ]; then
    echo "Cleaning up existing model directory..."
    rm -rf "$MODEL_DIR"
fi

if [ -d "$SCENARIO_DIR" ]; then
    echo "Cleaning up existing scenario directory..."
    rm -rf "$SCENARIO_DIR"
fi

if [ -f "$REPORT_FILE" ]; then
    rm -f "$REPORT_FILE"
fi

# Ensure user directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Ensure Bridge Command data directory permissions allow the agent to create models
# (Usually /opt/bridgecommand is owned by root, but for this task agent needs write access)
if [ -d "/opt/bridgecommand/Models" ]; then
    chmod 777 "/opt/bridgecommand/Models"
fi
if [ -d "/opt/bridgecommand/Scenarios" ]; then
    chmod 777 "/opt/bridgecommand/Scenarios"
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="