#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Adapt Example Code Result ==="

WORKSPACE_DIR="/home/ga/workspace/datavalidator"
RESULTS_DIR="/tmp/task_results"

# Ensure workspace exists
if [ ! -d "$WORKSPACE_DIR" ]; then
    echo "⚠️ Workspace directory not found"
    exit 0
fi

# Try to save current file in VSCode
echo "Attempting to save current file..."
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Could not send save command to VSCode"
}

sleep 2

# Create results directory
mkdir -p "$RESULTS_DIR"

# Copy the modified validator file
if [ -f "$WORKSPACE_DIR/pipeline/validator.py" ]; then
    cp "$WORKSPACE_DIR/pipeline/validator.py" "$RESULTS_DIR/validator.py"
    echo "✅ Copied validator.py to $RESULTS_DIR"
else
    echo "⚠️ validator.py not found at $WORKSPACE_DIR/pipeline/validator.py"
fi

# Copy the original example for reference
if [ -f "$WORKSPACE_DIR/docs/example_validator.py" ]; then
    cp "$WORKSPACE_DIR/docs/example_validator.py" "$RESULTS_DIR/example_validator.py"
    echo "✅ Copied example_validator.py to $RESULTS_DIR"
fi

# Export git diff if any changes were committed
cd "$WORKSPACE_DIR"
if [ -d ".git" ]; then
    sudo -u ga git diff HEAD pipeline/validator.py > "$RESULTS_DIR/validator_diff.txt" 2>&1 || true
    echo "✅ Exported git diff"
fi

echo "✅ Export complete"
echo "Results location: $RESULTS_DIR"
ls -la "$RESULTS_DIR"