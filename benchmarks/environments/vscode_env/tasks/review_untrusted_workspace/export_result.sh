#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Review Untrusted Workspace Result ==="

WORKSPACE_DIR="/home/ga/workspace/untrusted_pr"

# Ensure any open files are saved
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
} || {
    echo "⚠️ Failed to send save command; continuing"
}

# Wait for files to be written
sleep 2

# Export the security review document
if [ -f "$WORKSPACE_DIR/SECURITY_REVIEW.md" ]; then
    cp "$WORKSPACE_DIR/SECURITY_REVIEW.md" /tmp/security_review.md
    echo "✅ Exported SECURITY_REVIEW.md"
    echo "Preview:"
    head -20 /tmp/security_review.md
else
    echo "⚠️ SECURITY_REVIEW.md not found"
    echo "" > /tmp/security_review.md
fi

# Export the trust checklist
if [ -f "$WORKSPACE_DIR/TRUST_CHECKLIST.md" ]; then
    cp "$WORKSPACE_DIR/TRUST_CHECKLIST.md" /tmp/trust_checklist.md
    echo "✅ Exported TRUST_CHECKLIST.md"
    echo "Preview:"
    head -20 /tmp/trust_checklist.md
else
    echo "⚠️ TRUST_CHECKLIST.md not found"
    echo "" > /tmp/trust_checklist.md
fi

# Export workspace config files for debugging (verifier doesn't need these)
mkdir -p /tmp/workspace_config
cp -r "$WORKSPACE_DIR/.vscode"/* /tmp/workspace_config/ 2>/dev/null || true
cp "$WORKSPACE_DIR/package.json" /tmp/workspace_config/ 2>/dev/null || true

echo "✅ Export complete"
echo "Files exported to /tmp for verification"