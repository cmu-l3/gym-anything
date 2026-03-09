#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Debug Background Worker Result ==="

WORKSPACE_DIR="/home/ga/workspace/thumbnail_service"

# Give time for any file operations to complete
sleep 2

# Try to save any open files in VSCode
focus_vscode_window 2>/dev/null || true
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s  # Save all
    sleep 1
} || true

# Export configuration files
echo "Exporting configuration files..."
cp "$WORKSPACE_DIR/config.yaml" /tmp/config.yaml 2>/dev/null || echo "thumbnail_width: 0" > /tmp/config.yaml
cp "$WORKSPACE_DIR/queue.json" /tmp/queue.json 2>/dev/null || echo "[]" > /tmp/queue.json

# Export launch configuration if exists
if [ -f "$WORKSPACE_DIR/.vscode/launch.json" ]; then
    cp "$WORKSPACE_DIR/.vscode/launch.json" /tmp/launch.json
    echo "✓ Launch configuration exported"
else
    echo "{}" > /tmp/launch.json
    echo "⚠️ No launch.json found"
fi

# Export output directory listing
if [ -d "$WORKSPACE_DIR/output" ]; then
    ls -la "$WORKSPACE_DIR/output" > /tmp/output_listing.txt 2>&1
    # Count files
    file_count=$(find "$WORKSPACE_DIR/output" -type f 2>/dev/null | wc -l)
    echo "✓ Output directory has $file_count files"
else
    echo "No output directory" > /tmp/output_listing.txt
fi

# Try to run worker if it hasn't been run yet (to be lenient)
# Check if any jobs are still pending
pending_count=$(grep -c '"status": "pending"' "$WORKSPACE_DIR/queue.json" 2>/dev/null || echo "0")
if [ "$pending_count" -gt 0 ]; then
    echo "📝 Note: Found $pending_count pending jobs (worker may not have been run yet)"
fi

# Export worker log if it was created
if [ -f "$WORKSPACE_DIR/worker.log" ]; then
    cp "$WORKSPACE_DIR/worker.log" /tmp/worker.log
fi

echo "✅ Export complete"
echo "Exported files:"
echo "  - /tmp/config.yaml"
echo "  - /tmp/queue.json"
echo "  - /tmp/launch.json"
echo "  - /tmp/output_listing.txt"