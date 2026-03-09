#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Create Teaching Example Result ==="

TARGET_FILE="/home/ga/workspace/teaching-materials/async-await-demo.js"
EXPORT_DIR="/tmp/task_results/create_teaching_example"

# Ensure VSCode window is focused and trigger save
focus_vscode_window
{
    echo "Triggering save operation..."
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 2
} || {
    echo "⚠️ Failed to trigger save; continuing anyway"
}

# Wait for file to be written
sleep 1

# Create export directory
mkdir -p "$EXPORT_DIR"

# Export the teaching example file if it exists
if [ -f "$TARGET_FILE" ]; then
    cp "$TARGET_FILE" "$EXPORT_DIR/async-await-demo.js"
    
    # Also copy to /tmp for verifier (some verifiers expect files in /tmp)
    cp "$TARGET_FILE" "/tmp/async-await-demo.js"
    
    echo "✅ Teaching example file exported"
    echo "File size: $(stat -c%s "$TARGET_FILE") bytes"
    echo "Line count: $(wc -l < "$TARGET_FILE") lines"
else
    echo "⚠️ Teaching example file not found at $TARGET_FILE"
    echo "" > "/tmp/async-await-demo.js"
fi

# Export README for context
if [ -f "/home/ga/workspace/teaching-materials/README.md" ]; then
    cp "/home/ga/workspace/teaching-materials/README.md" "$EXPORT_DIR/"
fi

# Create a summary file
cat > "$EXPORT_DIR/export_summary.txt" << EOF
Export Summary for create_teaching_example@1
============================================
Target file: $TARGET_FILE
File exists: $([ -f "$TARGET_FILE" ] && echo "YES" || echo "NO")
Timestamp: $(date)
EOF

if [ -f "$TARGET_FILE" ]; then
    cat >> "$EXPORT_DIR/export_summary.txt" << EOF
File size: $(stat -c%s "$TARGET_FILE") bytes
Line count: $(wc -l < "$TARGET_FILE") lines
First 5 lines:
$(head -5 "$TARGET_FILE")
EOF
fi

echo "✅ Export complete"
echo "Results exported to: $EXPORT_DIR"