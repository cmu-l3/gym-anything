#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Technical Debt Catalog Result ==="

# Focus VSCode and attempt to save any open files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to focus VSCode window; continuing"
}

# Wait for potential file saves
sleep 2

# Check if TECHNICAL_DEBT.md exists
DEBT_DOC="/home/ga/workspace/debt_project/TECHNICAL_DEBT.md"

if [ -f "$DEBT_DOC" ]; then
    echo "✅ TECHNICAL_DEBT.md found"
    echo "File size: $(stat -f%z "$DEBT_DOC" 2>/dev/null || stat -c%s "$DEBT_DOC" 2>/dev/null || echo 'unknown') bytes"
    
    # Copy to /tmp for verifier
    cp "$DEBT_DOC" /tmp/TECHNICAL_DEBT.md 2>/dev/null || sudo -u ga cp "$DEBT_DOC" /tmp/TECHNICAL_DEBT.md
    
    echo "Preview of content:"
    head -n 20 "$DEBT_DOC" 2>/dev/null || echo "Could not preview file"
else
    echo "⚠️ TECHNICAL_DEBT.md not found at $DEBT_DOC"
    echo "Creating empty marker file for verifier"
    echo "" > /tmp/TECHNICAL_DEBT.md
fi

# Export workspace file listing for debugging
find /home/ga/workspace/debt_project -type f -name "*.md" > /tmp/workspace_md_files.txt 2>/dev/null || echo "" > /tmp/workspace_md_files.txt

echo "✅ Export complete"
echo "Documentation file: $DEBT_DOC"