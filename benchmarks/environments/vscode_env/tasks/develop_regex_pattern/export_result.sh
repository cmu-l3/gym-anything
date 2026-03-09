#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Develop Regex Pattern Result ==="

WORKSPACE_DIR="/home/ga/workspace/log_parser"

# Focus VSCode and attempt to save all files
focus_vscode_window
sleep 1

# Save all open files
echo "Saving all files..."
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
    safe_xdotool ga :1 key --delay 100 ctrl+s
} || {
    echo "⚠️ Failed to send save command; continuing"
}

sleep 2

# Wait for expected output files
echo "Waiting for output files..."
wait_for_file "$WORKSPACE_DIR/pattern.txt" 3 || echo "⚠️ pattern.txt not found yet"
wait_for_file "$WORKSPACE_DIR/test_results.txt" 2 || echo "⚠️ test_results.txt not found yet"
wait_for_file "$WORKSPACE_DIR/pattern_explanation.md" 2 || echo "⚠️ pattern_explanation.md not found yet"

# Export file listings for debugging
echo "Listing workspace files..."
ls -lah "$WORKSPACE_DIR" > /tmp/log_parser_files.txt 2>&1 || echo "Failed to list files" > /tmp/log_parser_files.txt

# Copy outputs to /tmp for easier verification access
if [ -f "$WORKSPACE_DIR/pattern.txt" ]; then
    cp "$WORKSPACE_DIR/pattern.txt" /tmp/regex_pattern.txt 2>/dev/null || true
    echo "✅ pattern.txt exported"
else
    echo "❌ pattern.txt not found"
fi

if [ -f "$WORKSPACE_DIR/test_results.txt" ]; then
    cp "$WORKSPACE_DIR/test_results.txt" /tmp/regex_test_results.txt 2>/dev/null || true
    echo "✅ test_results.txt exported"
else
    echo "❌ test_results.txt not found"
fi

if [ -f "$WORKSPACE_DIR/pattern_explanation.md" ]; then
    cp "$WORKSPACE_DIR/pattern_explanation.md" /tmp/regex_explanation.md 2>/dev/null || true
    echo "✅ pattern_explanation.md exported"
else
    echo "❌ pattern_explanation.md not found"
fi

echo "✅ Export complete"
echo "Workspace: $WORKSPACE_DIR"