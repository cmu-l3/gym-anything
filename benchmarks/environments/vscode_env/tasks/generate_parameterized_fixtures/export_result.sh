#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Generate Parameterized Fixtures Result ==="

WORKSPACE_DIR="/home/ga/workspace/test_fixtures"
OUTPUT_DIR="/tmp/fixture_task_output"

# Focus VSCode and save all files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
} || {
    echo "⚠️ Failed to save files via keyboard; continuing"
}

# Wait for file to be written
sleep 2

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Copy the generated fixture file
if [ -f "$WORKSPACE_DIR/users_fixture.json" ]; then
    cp "$WORKSPACE_DIR/users_fixture.json" "$OUTPUT_DIR/"
    echo "✅ Exported users_fixture.json"
    
    # Show file size and first few lines for debugging
    echo "File size: $(wc -c < "$WORKSPACE_DIR/users_fixture.json") bytes"
    echo "First 200 characters:"
    head -c 200 "$WORKSPACE_DIR/users_fixture.json" || true
else
    echo "❌ users_fixture.json not found at $WORKSPACE_DIR"
    # List what files are present
    echo "Files in workspace:"
    ls -la "$WORKSPACE_DIR" || true
fi

# Also copy workspace for debugging
cp -r "$WORKSPACE_DIR" "$OUTPUT_DIR/workspace_snapshot" 2>/dev/null || true

echo "✅ Export complete"
echo "Output directory: $OUTPUT_DIR"