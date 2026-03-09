#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Benchmark Optimization Result ==="

# Ensure any open files are saved
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to save files; continuing"
}

# Wait for files to be written
WORKSPACE_DIR="/home/ga/workspace/benchmark_task"
wait_for_file "$WORKSPACE_DIR/data_processor.py" 3

# Export key files to /tmp for easier verification access
echo "Exporting files to /tmp..."
cp "$WORKSPACE_DIR/data_processor.py" /tmp/data_processor.py 2>/dev/null || echo "data_processor.py not copied"
cp "$WORKSPACE_DIR/benchmark_report.txt" /tmp/benchmark_report.txt 2>/dev/null || echo "benchmark_report.txt not found"
cp "$WORKSPACE_DIR/output.json" /tmp/output.json 2>/dev/null || echo "output.json not copied"
cp "$WORKSPACE_DIR/output_original.json" /tmp/output_original.json 2>/dev/null || echo "output_original.json not found"

echo "✅ Export complete"
echo "Workspace: $WORKSPACE_DIR"
ls -la "$WORKSPACE_DIR/" || true