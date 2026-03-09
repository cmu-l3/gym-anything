#!/bin/bash
# set -euo pipefail

echo "=== Exporting CSV Transformation Validation Result ==="

WORKSPACE_DIR="/home/ga/workspace/data_validation"
RESULTS_DIR="/tmp/task_results"

mkdir -p "$RESULTS_DIR"

# Copy generated output if it exists
if [ -f "$WORKSPACE_DIR/actual_output.csv" ]; then
    cp "$WORKSPACE_DIR/actual_output.csv" "$RESULTS_DIR/"
    echo "✅ Copied actual_output.csv"
else
    echo "⚠️ actual_output.csv not found"
fi

# Copy validation confirmation if it exists
if [ -f "$WORKSPACE_DIR/validation_passed.txt" ]; then
    cp "$WORKSPACE_DIR/validation_passed.txt" "$RESULTS_DIR/"
    echo "✅ Copied validation_passed.txt"
else
    echo "⚠️ validation_passed.txt not found"
fi

# Copy expected output for verification reference
if [ -f "$WORKSPACE_DIR/expected_output.csv" ]; then
    cp "$WORKSPACE_DIR/expected_output.csv" "$RESULTS_DIR/"
    echo "✅ Copied expected_output.csv"
fi

# Copy sample input for reference
if [ -f "$WORKSPACE_DIR/sample_input.csv" ]; then
    cp "$WORKSPACE_DIR/sample_input.csv" "$RESULTS_DIR/"
    echo "✅ Copied sample_input.csv"
fi

# Export VSCode storage data to check for diff viewer usage (optional)
if [ -f "/home/ga/.config/Code/User/globalStorage/storage.json" ]; then
    cp "/home/ga/.config/Code/User/globalStorage/storage.json" "$RESULTS_DIR/" 2>/dev/null || true
fi

# Export bash history to check if command was run
if [ -f "/home/ga/.bash_history" ]; then
    tail -20 /home/ga/.bash_history > "$RESULTS_DIR/bash_history.txt" 2>/dev/null || true
fi

echo "✅ Export complete: $RESULTS_DIR"
ls -la "$RESULTS_DIR"