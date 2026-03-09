#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting DevContainer Onboarding Result ==="

WORKSPACE_DIR="/home/ga/workspace/team_project"

# Focus VSCode and save all files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
    safe_xdotool ga :1 key --delay 100 ctrl+s
} || {
    echo "⚠️ Failed to save files via VSCode; continuing"
}

sleep 2

# Wait for key files to be potentially created
wait_for_file "$WORKSPACE_DIR/.devcontainer/devcontainer.json" 2 || true
wait_for_file "$WORKSPACE_DIR/.vscode/settings.json" 2 || true
wait_for_file "$WORKSPACE_DIR/QUICKSTART.md" 2 || true

# Copy configuration files to /tmp for verification
mkdir -p /tmp/task_output/devcontainer_verification

echo "Copying devcontainer configuration..."
if [ -d "$WORKSPACE_DIR/.devcontainer" ]; then
    cp -r "$WORKSPACE_DIR/.devcontainer" /tmp/task_output/devcontainer_verification/ 2>/dev/null || true
    echo "✅ .devcontainer/ copied"
else
    echo "⚠️ .devcontainer/ directory not found"
fi

echo "Copying VSCode workspace configuration..."
if [ -d "$WORKSPACE_DIR/.vscode" ]; then
    cp -r "$WORKSPACE_DIR/.vscode" /tmp/task_output/devcontainer_verification/ 2>/dev/null || true
    echo "✅ .vscode/ copied"
else
    echo "⚠️ .vscode/ directory not found"
fi

echo "Copying QUICKSTART guide..."
if [ -f "$WORKSPACE_DIR/QUICKSTART.md" ]; then
    cp "$WORKSPACE_DIR/QUICKSTART.md" /tmp/task_output/devcontainer_verification/ 2>/dev/null || true
    echo "✅ QUICKSTART.md copied"
else
    echo "⚠️ QUICKSTART.md not found"
fi

# Create manifest of created files
echo "Creating verification manifest..."
cat > /tmp/task_output/manifest.txt << EOF
DevContainer Onboarding Setup - File Manifest
==============================================

Created files:
$(find "$WORKSPACE_DIR" -type f \( -path "*/.devcontainer/*" -o -path "*/.vscode/*" -o -name "QUICKSTART.md" \) 2>/dev/null | sed "s|$WORKSPACE_DIR|.|g" || echo "None found")

Timestamp: $(date)
EOF

echo "✅ Export complete"
echo "📁 Exported to: /tmp/task_output/devcontainer_verification/"
ls -la /tmp/task_output/devcontainer_verification/ 2>/dev/null || echo "No files exported"