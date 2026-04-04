#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Automate Full-Stack Dev Start Result ==="

WORKSPACE_DIR="/home/ga/workspace/fullstack-project"
OUTPUT_DIR="/tmp/task_output"

mkdir -p "$OUTPUT_DIR"

# Give any running tasks time to complete initialization
sleep 2

# Export tasks.json if it exists
echo "Checking for tasks.json..."
if [ -f "$WORKSPACE_DIR/.vscode/tasks.json" ]; then
    cp "$WORKSPACE_DIR/.vscode/tasks.json" "$OUTPUT_DIR/tasks.json"
    echo "✅ tasks.json copied to output"
    
    # Show preview
    echo "Preview of tasks.json:"
    head -20 "$WORKSPACE_DIR/.vscode/tasks.json"
else
    echo "⚠️  tasks.json not found at $WORKSPACE_DIR/.vscode/tasks.json"
    echo "null" > "$OUTPUT_DIR/tasks.json"
fi

# Check if database was created (evidence that tasks were executed)
echo "Checking for database file..."
if [ -f "/tmp/dev.db" ]; then
    echo "✅ Database file exists at /tmp/dev.db (tasks likely executed)"
    cp "/tmp/dev.db" "$OUTPUT_DIR/dev.db" 2>/dev/null || true
    
    # Get table count as evidence
    TABLE_COUNT=$(sqlite3 /tmp/dev.db "SELECT COUNT(*) FROM sqlite_master WHERE type='table';" 2>/dev/null || echo "0")
    echo "   Tables in database: $TABLE_COUNT"
    echo "$TABLE_COUNT" > "$OUTPUT_DIR/db_table_count.txt"
else
    echo "ℹ️  Database not found (tasks may not have been executed yet)"
    echo "0" > "$OUTPUT_DIR/db_table_count.txt"
fi

# Export .vscode directory listing for debugging
ls -la "$WORKSPACE_DIR/.vscode/" > "$OUTPUT_DIR/vscode_dir_listing.txt" 2>&1 || echo "No .vscode directory" > "$OUTPUT_DIR/vscode_dir_listing.txt"

# Export workspace structure for debugging
tree -L 3 "$WORKSPACE_DIR" > "$OUTPUT_DIR/workspace_structure.txt" 2>/dev/null || ls -laR "$WORKSPACE_DIR" > "$OUTPUT_DIR/workspace_structure.txt" 2>&1

echo ""
echo "✅ Export complete"
echo "📁 Output directory: $OUTPUT_DIR"
echo "📄 Files exported:"
ls -lh "$OUTPUT_DIR/" 2>/dev/null || true