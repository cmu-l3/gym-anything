#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Remove Debug Logging Result ==="

WORKSPACE_DIR="/home/ga/workspace/data_processor"

# Ensure files are saved
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+k s
    sleep 1
} || {
    echo "⚠️ Failed to trigger save; continuing"
}

# Wait a moment for file system sync
sleep 2

# Create export directory
EXPORT_DIR="/tmp/debug_cleanup_export"
mkdir -p "$EXPORT_DIR"

# Export all relevant files for verification
if [ -d "$WORKSPACE_DIR" ]; then
    echo "Exporting workspace files..."
    
    # Copy all Python files from src/
    if [ -d "$WORKSPACE_DIR/src" ]; then
        cp "$WORKSPACE_DIR/src/processor.py" "$EXPORT_DIR/" 2>/dev/null || echo "processor.py not found"
        cp "$WORKSPACE_DIR/src/worker.py" "$EXPORT_DIR/" 2>/dev/null || echo "worker.py not found"
        cp "$WORKSPACE_DIR/src/config.py" "$EXPORT_DIR/" 2>/dev/null || echo "config.py not found"
        cp "$WORKSPACE_DIR/src/utils.py" "$EXPORT_DIR/" 2>/dev/null || echo "utils.py not found"
        cp "$WORKSPACE_DIR/src/logger.py" "$EXPORT_DIR/" 2>/dev/null || echo "logger.py not found"
    fi
    
    # Copy test file
    if [ -d "$WORKSPACE_DIR/tests" ]; then
        cp "$WORKSPACE_DIR/tests/test_processor.py" "$EXPORT_DIR/" 2>/dev/null || echo "test_processor.py not found"
    fi
    
    echo "Files exported to $EXPORT_DIR"
    ls -la "$EXPORT_DIR"
else
    echo "⚠️ Workspace directory not found: $WORKSPACE_DIR"
fi

echo "✅ Export complete"