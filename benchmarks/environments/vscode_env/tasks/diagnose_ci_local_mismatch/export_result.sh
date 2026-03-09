#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Diagnose CI/Local Mismatch Result ==="

WORKSPACE_DIR="/home/ga/workspace/timestamp_service"
DIAGNOSIS_FILE="$WORKSPACE_DIR/CI_MISMATCH_DIAGNOSIS.md"

# Ensure VSCode saves any open files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to send save command; continuing"
}

# Wait for diagnosis file to be written
wait_for_file "$DIAGNOSIS_FILE" 5 || echo "⚠️ Diagnosis file not found yet"

# Export the diagnosis file to /tmp for verifier
if [ -f "$DIAGNOSIS_FILE" ]; then
    cp "$DIAGNOSIS_FILE" /tmp/ci_diagnosis.md
    echo "✅ Diagnosis file exported to /tmp/ci_diagnosis.md"
    echo "Preview:"
    head -20 "$DIAGNOSIS_FILE"
else
    echo "❌ Diagnosis file not found at $DIAGNOSIS_FILE"
    touch /tmp/ci_diagnosis.md  # Create empty file for verifier
fi

# Also export the workflow file for reference
if [ -f "$WORKSPACE_DIR/.github/workflows/ci.yml" ]; then
    cp "$WORKSPACE_DIR/.github/workflows/ci.yml" /tmp/ci_workflow.yml
fi

echo "✅ Export complete"
echo "Workspace: $WORKSPACE_DIR"