#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Trace Cryptic Error Task ==="

WORKSPACE_DIR="/home/ga/workspace/debug_task"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Copy buggy script and test data
ASSETS_DIR="/workspace/tasks/trace_cryptic_error/assets"
sudo -u ga cp "$ASSETS_DIR/data_processor.py" "$WORKSPACE_DIR/"
sudo -u ga cp "$ASSETS_DIR/test_data.json" "$WORKSPACE_DIR/"

# Create a README for the task
cat > "$WORKSPACE_DIR/TASK.md" << 'EOF'
# Debug Task

The script `data_processor.py` fails with a cryptic error: