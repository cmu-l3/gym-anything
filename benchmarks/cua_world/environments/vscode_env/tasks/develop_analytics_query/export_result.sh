#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Develop Analytics Query Result ==="

WORKSPACE_DIR="/home/ga/workspace/sales_analysis"

# Focus VSCode and save all files
focus_vscode_window
{
    echo "Saving all files in VSCode..."
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to send save command; continuing"
}

# Wait for query file to be written
sleep 2

# Copy query solution if it exists
if [ -f "$WORKSPACE_DIR/query_solution.sql" ]; then
    echo "✅ Found query_solution.sql, copying to /tmp"
    cp "$WORKSPACE_DIR/query_solution.sql" /tmp/query_solution.sql
    echo "Query file size: $(wc -c < "$WORKSPACE_DIR/query_solution.sql") bytes"
else
    echo "⚠️ query_solution.sql not found in workspace"
    echo "NOT_FOUND" > /tmp/query_solution.sql
fi

# Copy database and expected output for verification
if [ -f "$WORKSPACE_DIR/sales.db" ]; then
    cp "$WORKSPACE_DIR/sales.db" /tmp/sales.db
    echo "✅ Database copied to /tmp"
fi

if [ -f "$WORKSPACE_DIR/expected_output.csv" ]; then
    cp "$WORKSPACE_DIR/expected_output.csv" /tmp/expected_output.csv
    echo "✅ Expected output copied to /tmp"
fi

# List workspace contents for debugging
echo ""
echo "Workspace contents:"
ls -lh "$WORKSPACE_DIR/"

echo ""
echo "✅ Export complete"