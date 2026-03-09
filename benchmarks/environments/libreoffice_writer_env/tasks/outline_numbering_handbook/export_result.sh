#!/bin/bash
set -e

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Results ==="

# 1. Capture final screenshot (CRITICAL for VLM)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check if output file exists
OUTPUT_FILE="/home/ga/Documents/handbook_numbered.docx"
TXT_EXPORT="/home/ga/Documents/handbook_numbered.txt"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    # Check modification time
    MTIME=$(stat -c %Y "$OUTPUT_FILE")
    if [ "$MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # 3. CRITICAL: Generate text export for verifier to check numbering
    # We do this INSIDE the container because verifier runs on host (no LibreOffice)
    # The text export of numbered lists typically renders the numbers as text (e.g., "1. Introduction")
    echo "Exporting DOCX to TXT for numbering verification..."
    
    # Kill running Writer to release file lock if needed, or use headless safely
    # We'll try running headless conversion. It usually works even if GUI is open if we use a different user dir or just try.
    # Safe approach: Copy to temp first
    cp "$OUTPUT_FILE" /tmp/verify_temp.docx
    chown ga:ga /tmp/verify_temp.docx
    
    su - ga -c "libreoffice --headless --convert-to txt:Text --outdir /home/ga/Documents /tmp/verify_temp.docx" || true
    
    # Rename if needed (LibreOffice keeps filename)
    if [ -f "/home/ga/Documents/verify_temp.txt" ]; then
        mv "/home/ga/Documents/verify_temp.txt" "$TXT_EXPORT"
    fi
    
    rm -f /tmp/verify_temp.docx
else
    echo "Output file $OUTPUT_FILE not found."
fi

# 4. JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "txt_export_exists": $([ -f "$TXT_EXPORT" ] && echo "true" || echo "false"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to standardized location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="