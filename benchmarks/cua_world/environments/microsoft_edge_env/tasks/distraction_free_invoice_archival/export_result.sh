#!/bin/bash
# export_result.sh - Post-task hook for Distraction-Free Invoice Archival
# Extracts text from the generated PDF and exports verification data.

echo "=== Exporting task results ==="

# Constants
PDF_PATH="/home/ga/Documents/Invoices/invoice_8492_clean.pdf"
TASK_START_FILE="/tmp/task_start_time.txt"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get Task Start Time
TASK_START=0
if [ -f "$TASK_START_FILE" ]; then
    TASK_START=$(cat "$TASK_START_FILE")
fi

# 3. Analyze the PDF Output
PDF_EXISTS="false"
PDF_SIZE=0
PDF_MODIFIED_AFTER_START="false"
PDF_CONTENT_TEXT=""

if [ -f "$PDF_PATH" ]; then
    PDF_EXISTS="true"
    PDF_SIZE=$(stat -c %s "$PDF_PATH")
    
    # Check modification time
    PDF_MTIME=$(stat -c %Y "$PDF_PATH")
    if [ "$PDF_MTIME" -gt "$TASK_START" ]; then
        PDF_MODIFIED_AFTER_START="true"
    fi

    # Extract text content using pdftotext (installed in setup)
    # We use python to JSON-escape the content to ensure valid JSON output
    PDF_CONTENT_TEXT=$(pdftotext "$PDF_PATH" - 2>/dev/null | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))')
else
    PDF_CONTENT_TEXT='""'
fi

# 4. Check if Edge is still running
APP_RUNNING="false"
if pgrep -f "microsoft-edge" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create Result JSON
# Using python for safe JSON generation to handle variable content
python3 << EOF > /tmp/task_result.json
import json

result = {
    "task_start": $TASK_START,
    "pdf_exists": $PDF_EXISTS,
    "pdf_size": $PDF_SIZE,
    "pdf_modified_after_start": $PDF_MODIFIED_AFTER_START,
    "pdf_content": $PDF_CONTENT_TEXT,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="