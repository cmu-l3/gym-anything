#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Extract Hardcoded Secrets Result ==="

WORKSPACE_DIR="/home/ga/workspace/weather_api_project"

# Focus VSCode and save all
focus_vscode_window
{
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to trigger save; continuing"
}

sleep 2

# Wait for files to be written
wait_for_file "$WORKSPACE_DIR/main.py" 5
wait_for_file "$WORKSPACE_DIR/.gitignore" 5

# Copy files to /tmp for verification
echo "Copying files for verification..."

# Copy main.py
if [ -f "$WORKSPACE_DIR/main.py" ]; then
    cp "$WORKSPACE_DIR/main.py" /tmp/main.py
    echo "✅ main.py copied"
else
    echo "⚠️ main.py not found"
    echo "" > /tmp/main.py
fi

# Copy .env if it exists
if [ -f "$WORKSPACE_DIR/.env" ]; then
    cp "$WORKSPACE_DIR/.env" /tmp/dotenv_file
    echo "✅ .env copied"
else
    echo "⚠️ .env not found"
    echo "" > /tmp/dotenv_file
fi

# Copy .gitignore
if [ -f "$WORKSPACE_DIR/.gitignore" ]; then
    cp "$WORKSPACE_DIR/.gitignore" /tmp/gitignore_file
    echo "✅ .gitignore copied"
else
    echo "⚠️ .gitignore not found"
    echo "" > /tmp/gitignore_file
fi

# Also copy requirements.txt for reference
if [ -f "$WORKSPACE_DIR/requirements.txt" ]; then
    cp "$WORKSPACE_DIR/requirements.txt" /tmp/requirements.txt
fi

# Create a manifest file listing what was exported
cat > /tmp/export_manifest.txt << EOF
Exported files from: $WORKSPACE_DIR
Timestamp: $(date)
Files:
  - main.py: $([ -f "$WORKSPACE_DIR/main.py" ] && echo "exists" || echo "missing")
  - .env: $([ -f "$WORKSPACE_DIR/.env" ] && echo "exists" || echo "missing")
  - .gitignore: $([ -f "$WORKSPACE_DIR/.gitignore" ] && echo "exists" || echo "missing")
EOF

echo "✅ Export complete"
echo "Files exported to /tmp for verification"