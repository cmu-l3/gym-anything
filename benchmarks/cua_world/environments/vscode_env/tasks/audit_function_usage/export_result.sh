#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Audit Function Usage Result ==="

WORKSPACE_DIR="/home/ga/workspace/ecommerce_app"

# Focus VSCode and save all files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to send save commands; continuing"
}

# Wait for files to be written
sleep 2

# Export key files to /tmp for verification
echo "Exporting files for verification..."

if [ -f "$WORKSPACE_DIR/REFACTOR_PLAN.md" ]; then
    cp "$WORKSPACE_DIR/REFACTOR_PLAN.md" /tmp/refactor_plan.md
    echo "✅ Exported REFACTOR_PLAN.md"
else
    echo "⚠️ REFACTOR_PLAN.md not found"
    echo "" > /tmp/refactor_plan.md
fi

if [ -f "$WORKSPACE_DIR/pricing/calculator.py" ]; then
    cp "$WORKSPACE_DIR/pricing/calculator.py" /tmp/calculator.py
    echo "✅ Exported calculator.py"
else
    echo "⚠️ calculator.py not found"
fi

# Create export manifest
cat > /tmp/audit_task_manifest.json << EOF
{
  "task_id": "audit_function_usage@1",
  "export_timestamp": "$(date -Iseconds)",
  "workspace": "$WORKSPACE_DIR",
  "exported_files": [
    "REFACTOR_PLAN.md",
    "calculator.py"
  ]
}
EOF

echo "✅ Export complete"
echo "Files exported to /tmp/"