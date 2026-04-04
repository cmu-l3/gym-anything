#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Small Claims Evidence Timeline Result ==="

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

TIMELINE_DOC="/home/ga/Documents/TextDocuments/SmallClaims_Evidence_Timeline.docx"

if [ -f "$TIMELINE_DOC" ]; then
    echo "✅ Evidence timeline document saved: $TIMELINE_DOC"
    ls -lh "$TIMELINE_DOC"
else
    echo "⚠️ Evidence timeline document not found: $TIMELINE_DOC"
    echo "Checking for alternative locations..."
    find /home/ga/Documents -name "*Evidence*" -o -name "*SmallClaims*" 2>/dev/null || true
fi

# Also check if raw evidence document still exists
RAW_DOC="/home/ga/Documents/TextDocuments/evidence_raw.docx"
if [ -f "$RAW_DOC" ]; then
    echo "📄 Raw evidence document present: $RAW_DOC"
fi

echo "=== Export Complete ==="