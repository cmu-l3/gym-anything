#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Manuscript Submission Format Result ==="

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

SUBMISSION_PATH="/home/ga/Documents/TextDocuments/last_train_home_submission.docx"

if [ -f "$SUBMISSION_PATH" ]; then
    echo "✅ Submission manuscript saved: $SUBMISSION_PATH"
    ls -lh "$SUBMISSION_PATH"
else
    echo "⚠️ Submission manuscript not found at: $SUBMISSION_PATH"
    echo "Checking if draft was modified instead..."
    DRAFT_PATH="/home/ga/Documents/TextDocuments/last_train_home_draft.docx"
    if [ -f "$DRAFT_PATH" ]; then
        echo "📄 Draft exists: $DRAFT_PATH"
        ls -lh "$DRAFT_PATH"
    fi
fi

echo "=== Export Complete ==="