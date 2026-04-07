#!/bin/bash
set -e

echo "=== Exporting task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# --- File Extraction & Integrity Checks ---
PDF_PATH="/home/ga/Documents/Case_Files/fw9.pdf"
PDF_EXISTS="false"
PDF_CREATED_DURING_TASK="false"
PDF_HASH=""

if [ -f "$PDF_PATH" ]; then
    PDF_EXISTS="true"
    MTIME=$(stat -c %Y "$PDF_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -ge "$TASK_START" ]; then
        PDF_CREATED_DURING_TASK="true"
    fi
    PDF_HASH=$(sha256sum "$PDF_PATH" | awk '{print $1}')
fi

EXPECTED_HASH=$(sha256sum /tmp/ground_truth_fw9.pdf | awk '{print $1}')

# --- Archive Process Checks ---
# 1. Did they unzip it?
MBOX_EXTRACTED="false"
MBOX_EXTRACTED_COUNT=$(find /home/ga/Downloads /home/ga/.thunderbird -name "client_archive.mbox" 2>/dev/null | wc -l)
if [ "$MBOX_EXTRACTED_COUNT" -gt 0 ]; then
    MBOX_EXTRACTED="true"
fi

# 2. Did they open it in Thunderbird? (Thunderbird automatically generates an MSF file when parsing an MBOX)
MSF_EXISTS="false"
MSF_COUNT=$(find /home/ga/.thunderbird -name "client_archive*.msf" 2>/dev/null | wc -l)
if [ "$MSF_COUNT" -gt 0 ]; then
    MSF_EXISTS="true"
fi

# --- Compile JSON using Python ---
# Writing safely through Python prevents Bash escaping nightmares
python3 -c "
import json
data = {
    'task_start': int('$TASK_START' or 0),
    'task_end': int('$TASK_END' or 0),
    'pdf_exists': '$PDF_EXISTS' == 'true',
    'pdf_created_during_task': '$PDF_CREATED_DURING_TASK' == 'true',
    'pdf_hash': '$PDF_HASH',
    'expected_hash': '$EXPECTED_HASH',
    'mbox_extracted': '$MBOX_EXTRACTED' == 'true',
    'msf_exists': '$MSF_EXISTS' == 'true',
    'screenshot_path': '/tmp/task_final.png'
}
with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f)
"
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="