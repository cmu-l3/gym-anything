#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Accessibility Retrofit Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    save_document ga :1
    sleep 2

    # Close ONLYOFFICE
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is closed
if is_onlyoffice_running; then
    kill_onlyoffice ga
fi

# Wait a moment for file to be fully written
sleep 1

# Check both possible file locations
DRAFT_PATH="/home/ga/Documents/TextDocuments/community_resources_draft.docx"
ACCESSIBLE_PATH="/home/ga/Documents/TextDocuments/community_resources_accessible.docx"

echo "Checking for saved documents..."

if [ -f "$ACCESSIBLE_PATH" ]; then
    echo "✅ Accessible document saved: $ACCESSIBLE_PATH"
    ls -lh "$ACCESSIBLE_PATH"
elif [ -f "$DRAFT_PATH" ]; then
    echo "⚠️ Draft document found: $DRAFT_PATH"
    echo "   (Expected: community_resources_accessible.docx)"
    ls -lh "$DRAFT_PATH"
else
    echo "⚠️ No document found at expected locations"
fi

echo "=== Export Complete ==="