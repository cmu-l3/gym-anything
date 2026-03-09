#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Fix Cross-Platform Paths Result ==="

WORKSPACE_DIR="/home/ga/workspace/data-processor"

# Focus VSCode and save all files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
} || {
    echo "⚠️ Failed to trigger save all; continuing"
}

# Wait for files to be written
sleep 2

# Run test script and export results
cd "$WORKSPACE_DIR" || exit 1

echo "Running test script..."
sudo -u ga python3 test_paths.py > /tmp/test_paths_output.txt 2>&1
TEST_EXIT_CODE=$?
echo "Test exit code: $TEST_EXIT_CODE" >> /tmp/test_paths_output.txt

# Export test results
cp /tmp/test_paths_output.txt /tmp/test_paths_result.txt 2>/dev/null || echo "Test output not found" > /tmp/test_paths_result.txt

# Export file contents for verification
echo "Exporting modified files..."
cp "$WORKSPACE_DIR/main.py" /tmp/main_py.txt 2>/dev/null || echo "main.py not found" > /tmp/main_py.txt
cp "$WORKSPACE_DIR/config_loader.py" /tmp/config_loader_py.txt 2>/dev/null || echo "config_loader.py not found" > /tmp/config_loader_py.txt
cp "$WORKSPACE_DIR/data/processor.py" /tmp/processor_py.txt 2>/dev/null || echo "processor.py not found" > /tmp/processor_py.txt
cp "$WORKSPACE_DIR/utils/logger.py" /tmp/logger_py.txt 2>/dev/null || echo "logger.py not found" > /tmp/logger_py.txt

echo "✅ Export complete"
echo "Workspace: $WORKSPACE_DIR"
echo "Results exported to /tmp/"