#!/bin/bash
# set -euo pipefail

echo "=== Exporting Microservice Workspace Result ==="

WORKSPACE_FILE="/home/ga/projects/microservices.code-workspace"
OUTPUT_DIR="/tmp/workspace_output"
sudo -u ga mkdir -p "$OUTPUT_DIR"

# Give time for any file operations to complete
sleep 2

# Export workspace file if it exists
if [ -f "$WORKSPACE_FILE" ]; then
    echo "Workspace file found, copying to /tmp..."
    sudo -u ga cp "$WORKSPACE_FILE" "$OUTPUT_DIR/"
    echo "✅ Workspace file exported"
    
    # Show file content for debugging
    echo "Workspace file content:"
    cat "$WORKSPACE_FILE"
else
    echo "⚠️ Workspace file not found at $WORKSPACE_FILE"
    echo "File not found" > "$OUTPUT_DIR/workspace_not_found.txt"
fi

# Export list of open folders in VSCode
echo "Exporting VSCode state..."
sudo -u ga sh -c "DISPLAY=:1 wmctrl -l" > "$OUTPUT_DIR/window_list.txt" 2>/dev/null || echo "No windows" > "$OUTPUT_DIR/window_list.txt"

# List files in projects directory
ls -la /home/ga/projects/ > "$OUTPUT_DIR/projects_listing.txt" 2>/dev/null || echo "" > "$OUTPUT_DIR/projects_listing.txt"

# Try to get VSCode workspace storage info
VSCODE_STORAGE="/home/ga/.config/Code/User/workspaceStorage"
if [ -d "$VSCODE_STORAGE" ]; then
    ls -la "$VSCODE_STORAGE" > "$OUTPUT_DIR/workspace_storage.txt" 2>/dev/null || true
fi

sudo chown -R ga:ga "$OUTPUT_DIR"

echo "✅ Export complete"
echo "Workspace file location: $WORKSPACE_FILE"
echo "Output directory: $OUTPUT_DIR"