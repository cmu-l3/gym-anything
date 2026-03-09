#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Migrate CommonJS to ESM Result ==="

WORKSPACE_DIR="/home/ga/workspace/auth-service"

# Try to save any open files in VSCode
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 100 ctrl+s
    sleep 0.5
} || {
    echo "⚠️ Failed to send save command; continuing"
}

# Wait a moment for any pending writes
sleep 1

# Copy all relevant files to /tmp for verification
echo "Copying files to /tmp for verification..."

mkdir -p /tmp/auth-service-export/src/utils
mkdir -p /tmp/auth-service-export/test

# Copy package.json
if [ -f "$WORKSPACE_DIR/package.json" ]; then
    cp "$WORKSPACE_DIR/package.json" /tmp/auth-service-export/package.json
    echo "✅ Copied package.json"
else
    echo "⚠️ package.json not found"
fi

# Copy source files
for file in "src/auth.js" "src/utils/hash.js" "src/config.js" "test/auth.test.js"; do
    if [ -f "$WORKSPACE_DIR/$file" ]; then
        cp "$WORKSPACE_DIR/$file" "/tmp/auth-service-export/$file"
        echo "✅ Copied $file"
    else
        echo "⚠️ $file not found"
    fi
done

# Create a summary file with file info
cat > /tmp/auth-service-export/export_summary.txt << EOF
Export completed at $(date)
Workspace: $WORKSPACE_DIR
Files exported:
$(ls -lh /tmp/auth-service-export/)
EOF

echo "✅ Export complete"
echo "Files exported to: /tmp/auth-service-export/"
ls -la /tmp/auth-service-export/