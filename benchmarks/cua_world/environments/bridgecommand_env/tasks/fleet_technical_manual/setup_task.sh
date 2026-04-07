#!/bin/bash
echo "=== Setting up Fleet Technical Manual Task ==="

# Define paths
DOCS_DIR="/home/ga/Documents"
SCENARIO_ROOT="/opt/bridgecommand/Scenarios"
TARGET_SCENARIO="$SCENARIO_ROOT/z) Fleet Review"

# 1. Clean up previous artifacts
rm -f "$DOCS_DIR/fleet_technical_manual.txt"
rm -f "$DOCS_DIR/model_index.csv"
rm -rf "$TARGET_SCENARIO"

# Ensure Documents directory exists
mkdir -p "$DOCS_DIR"
chown ga:ga "$DOCS_DIR"

# 2. Record Task Start Time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Verify Environment (Models exist)
MODELS_DIR="/opt/bridgecommand/Models"
if [ ! -d "$MODELS_DIR" ]; then
    echo "ERROR: Models directory not found at $MODELS_DIR"
    exit 1
fi

MODEL_COUNT=$(ls -d "$MODELS_DIR"/*/ 2>/dev/null | wc -l)
echo "Found $MODEL_COUNT models in simulation environment."

# 4. Bridge Command setup
# Ensure BC is NOT running initially (this is a file task)
pkill -f "bridgecommand" 2>/dev/null || true

# 5. Take initial screenshot (Desktop state)
DISPLAY=:1 wmctrl -k on  # Show desktop
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="