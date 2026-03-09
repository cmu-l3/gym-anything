#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Rotate Exposed Credentials Result ==="

WORKSPACE_DIR="/home/ga/workspace/payment_service"

# Focus VSCode and save all files
focus_vscode_window
{
    echo "Saving all files..."
    safe_xdotool ga :1 key --delay 200 ctrl+k s
    sleep 1
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
} || {
    echo "⚠️ Failed to send save command; files may not be saved"
}

# Wait for files to be written
sleep 2

# Verify workspace exists
if [ ! -d "$WORKSPACE_DIR" ]; then
    echo "❌ Error: Workspace directory not found: $WORKSPACE_DIR"
    exit 1
fi

echo "✅ Export complete"
echo "Workspace files ready for verification at: $WORKSPACE_DIR"
echo ""
echo "Production files:"
ls -lh "$WORKSPACE_DIR/src/payment_client.py" 2>/dev/null || echo "  ⚠️ payment_client.py not found"
ls -lh "$WORKSPACE_DIR/src/utils/stripe_helper.js" 2>/dev/null || echo "  ⚠️ stripe_helper.js not found"
ls -lh "$WORKSPACE_DIR/config/production.yaml" 2>/dev/null || echo "  ⚠️ production.yaml not found"
ls -lh "$WORKSPACE_DIR/.env.example" 2>/dev/null || echo "  ⚠️ .env.example not found"
ls -lh "$WORKSPACE_DIR/.env.local" 2>/dev/null || echo "  ⚠️ .env.local not found"
echo ""
echo "Test files (should be unchanged):"
ls -lh "$WORKSPACE_DIR/tests/test_payment.py" 2>/dev/null || echo "  ⚠️ test_payment.py not found"
ls -lh "$WORKSPACE_DIR/tests/stripe.test.js" 2>/dev/null || echo "  ⚠️ stripe.test.js not found"
ls -lh "$WORKSPACE_DIR/README.md" 2>/dev/null || echo "  ⚠️ README.md not found"