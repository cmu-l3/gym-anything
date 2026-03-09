#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Analyze Production Logs Task ==="

WORKSPACE_DIR="/home/ga/workspace"
TASK_ASSETS="/workspace/tasks/analyze_production_logs/assets"

# Create directory structure
sudo -u ga mkdir -p "$WORKSPACE_DIR/logs"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src"

# Copy log file (800+ lines with critical error)
echo "Copying production log file..."
sudo -u ga cp "$TASK_ASSETS/payment_service.log" "$WORKSPACE_DIR/logs/"

# Copy source files
echo "Copying source files..."
sudo -u ga cp "$TASK_ASSETS/payment_processor.py" "$WORKSPACE_DIR/src/"
sudo -u ga cp "$TASK_ASSETS/transaction_handler.py" "$WORKSPACE_DIR/src/"
sudo -u ga cp "$TASK_ASSETS/api_client.py" "$WORKSPACE_DIR/src/"
sudo -u ga cp "$TASK_ASSETS/config.py" "$WORKSPACE_DIR/src/"
sudo -u ga cp "$TASK_ASSETS/README.md" "$WORKSPACE_DIR/"

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode in the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Open the log file to help the agent get started
echo "Opening log file..."
sleep 1
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/logs/payment_service.log'" 2>/dev/null || true
sleep 2

echo "=== Production Log Analysis Task Setup Complete ==="
echo "📝 Scenario:"
echo "  💥 Payment service is DOWN - critical production incident!"
echo "  📋 Log file: $WORKSPACE_DIR/logs/payment_service.log"
echo "  📂 Source code: $WORKSPACE_DIR/src/"
echo ""
echo "📝 Instructions:"
echo "  1. Analyze the log file (800+ lines) to find the CRITICAL error"
echo "  2. Identify the stack trace with file path and line number"
echo "  3. Navigate to that code location"
echo "  4. Add a TODO comment documenting the error"
echo "  5. Save the file"