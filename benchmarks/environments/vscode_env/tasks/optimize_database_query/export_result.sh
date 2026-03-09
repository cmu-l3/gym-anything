#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Optimize Database Query Result ==="

TARGET_FILE="/home/ga/workspace/analytics_db/top_products_by_category.sql"

# Try to save the file if VSCode is open
if pgrep -f "code" > /dev/null; then
    echo "Attempting to save file in VSCode..."
    focus_vscode_window
    {
        safe_xdotool ga :1 key --delay 200 ctrl+s
        sleep 1
    } || {
        echo "⚠️ Failed to send save command; file may already be saved"
    }
fi

# Wait for file to exist
wait_for_file "$TARGET_FILE" 3 || echo "⚠️ Warning: Target file not found at $TARGET_FILE"

# Copy to /tmp for easier verification access (optional, verifier will copy directly)
if [ -f "$TARGET_FILE" ]; then
    cp "$TARGET_FILE" /tmp/query_result.sql 2>/dev/null || true
    echo "✅ Query file found: $TARGET_FILE"
    echo "File size: $(stat -f%z "$TARGET_FILE" 2>/dev/null || stat -c%s "$TARGET_FILE" 2>/dev/null || echo 'unknown') bytes"
    echo "First 3 lines:"
    head -n 3 "$TARGET_FILE" 2>/dev/null || echo "(unable to read file)"
else
    echo "⚠️ Query file not found"
    touch /tmp/query_result.sql
fi

echo "✅ Export complete"