#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Batch Regex Refactor Result ==="

WORKSPACE_DIR="/home/ga/workspace/legacy-api-project"
EXPORT_DIR="/tmp/batch_regex_export"

# Ensure VSCode window is focused and save all files
focus_vscode_window
sleep 1

# Try to save all files
{
  safe_xdotool ga :1 key --delay 200 ctrl+k s
  sleep 1
  safe_xdotool ga :1 key --delay 200 ctrl+shift+s
  sleep 1
} || {
  echo "⚠️ Failed to send save commands; continuing"
}

# Wait for files to be saved
sleep 2

# Create export directory
mkdir -p "$EXPORT_DIR"

# Export the target files
echo "Exporting modified files..."
cp "$WORKSPACE_DIR/src/user-service.js" "$EXPORT_DIR/user-service.js" 2>/dev/null || echo "user-service.js not found" > "$EXPORT_DIR/user-service.js"
cp "$WORKSPACE_DIR/src/profile-manager.js" "$EXPORT_DIR/profile-manager.js" 2>/dev/null || echo "profile-manager.js not found" > "$EXPORT_DIR/profile-manager.js"
cp "$WORKSPACE_DIR/src/auth-handler.js" "$EXPORT_DIR/auth-handler.js" 2>/dev/null || echo "auth-handler.js not found" > "$EXPORT_DIR/auth-handler.js"
cp "$WORKSPACE_DIR/src/settings-controller.js" "$EXPORT_DIR/settings-controller.js" 2>/dev/null || true
cp "$WORKSPACE_DIR/src/dashboard.js" "$EXPORT_DIR/dashboard.js" 2>/dev/null || true

# Create a summary file with file stats
cat > "$EXPORT_DIR/summary.txt" << EOF
Batch Regex Refactor Export Summary
===================================
Workspace: $WORKSPACE_DIR
Export Time: $(date)

Target Files:
EOF

for file in user-service.js profile-manager.js auth-handler.js; do
  if [ -f "$WORKSPACE_DIR/src/$file" ]; then
    size=$(stat -f%z "$WORKSPACE_DIR/src/$file" 2>/dev/null || stat -c%s "$WORKSPACE_DIR/src/$file" 2>/dev/null || echo "unknown")
    modified=$(stat -f%Sm "$WORKSPACE_DIR/src/$file" 2>/dev/null || stat -c%y "$WORKSPACE_DIR/src/$file" 2>/dev/null || echo "unknown")
    echo "  - $file: $size bytes, modified: $modified" >> "$EXPORT_DIR/summary.txt"
  else
    echo "  - $file: NOT FOUND" >> "$EXPORT_DIR/summary.txt"
  fi
done

echo "✅ Export complete"
echo "Files exported to: $EXPORT_DIR"
ls -la "$EXPORT_DIR"
cat "$EXPORT_DIR/summary.txt"