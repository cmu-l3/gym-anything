#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Audit TODO Comments Result ==="

WORKSPACE_DIR="/home/ga/workspace/auth_service"

# Try to save any open files in VSCode
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to focus VSCode window; continuing"
}

# Wait for TODO_AUDIT.md to be created
wait_for_file "$WORKSPACE_DIR/TODO_AUDIT.md" 3 || true

# Export the TODO audit file to /tmp
if [ -f "$WORKSPACE_DIR/TODO_AUDIT.md" ]; then
    cp "$WORKSPACE_DIR/TODO_AUDIT.md" /tmp/TODO_AUDIT.md
    echo "✓ Exported TODO_AUDIT.md"
else
    echo "⚠️ TODO_AUDIT.md not found at $WORKSPACE_DIR"
    touch /tmp/TODO_AUDIT.md
fi

# Export source files to check if any TODOs were removed
cp "$WORKSPACE_DIR/auth.py" /tmp/auth_final.py 2>/dev/null || touch /tmp/auth_final.py
cp "$WORKSPACE_DIR/middleware.py" /tmp/middleware_final.py 2>/dev/null || touch /tmp/middleware_final.py
cp "$WORKSPACE_DIR/config.py" /tmp/config_final.py 2>/dev/null || touch /tmp/config_final.py

# Count TODO markers in final files (for verification)
echo "Counting TODO markers in final files..."
{
    grep -r -i -E "(TODO|FIXME|HACK|XXX|NOTE):" "$WORKSPACE_DIR/" 2>/dev/null | wc -l > /tmp/todo_count_final.txt
} || {
    echo "0" > /tmp/todo_count_final.txt
}

echo "✅ Export complete"
echo "Files exported to /tmp/"
ls -lh /tmp/TODO_AUDIT.md /tmp/*_final.py /tmp/todo_count_final.txt 2>/dev/null || true