#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Local Election Guide Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    save_document ga :1
    sleep 2

    # Try to close gracefully
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is closed
if is_onlyoffice_running; then
    echo "Force closing ONLYOFFICE..."
    kill_onlyoffice ga
    sleep 1
fi

# Wait a moment for file to be fully written
sleep 1

# Check for the expected output file
OUTPUT_FILE="/home/ga/Documents/TextDocuments/voter_guide.docx"

if [ -f "$OUTPUT_FILE" ]; then
    echo "✅ Voter guide saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    echo "⚠️ Expected file not found: $OUTPUT_FILE"
    echo "Checking for alternative filenames..."
    
    # Check if user saved with a different name
    find /home/ga/Documents/TextDocuments/ -name "*.docx" -type f -newer /tmp/onlyoffice_election_task.log 2>/dev/null || true
fi

echo "=== Export Complete ==="