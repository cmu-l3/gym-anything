#!/bin/bash
echo "=== Exporting Audit Competitor Access Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define expected paths
DOCS_DIR="/home/ga/Documents"
FILE_CSV="$DOCS_DIR/nexus_audit.csv"
FILE_PDF="$DOCS_DIR/nexus_audit.pdf"
FILE_TXT="$DOCS_DIR/nexus_audit.txt"
FILE_XLS="$DOCS_DIR/nexus_audit.xls"

# Check for output file
OUTPUT_FOUND="false"
OUTPUT_PATH=""
OUTPUT_CONTENT=""

# Priority: CSV > PDF > TXT > XLS
if [ -f "$FILE_CSV" ]; then
    OUTPUT_PATH="$FILE_CSV"
    OUTPUT_FOUND="true"
elif [ -f "$FILE_PDF" ]; then
    OUTPUT_PATH="$FILE_PDF"
    OUTPUT_FOUND="true"
elif [ -f "$FILE_TXT" ]; then
    OUTPUT_PATH="$FILE_TXT"
    OUTPUT_FOUND="true"
elif [ -f "$FILE_XLS" ]; then
    OUTPUT_PATH="$FILE_XLS"
    OUTPUT_FOUND="true"
fi

# Gather file stats
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ "$OUTPUT_FOUND" = "true" ]; then
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Extract content for verification (if text-based)
    if [[ "$OUTPUT_PATH" == *.csv ]] || [[ "$OUTPUT_PATH" == *.txt ]]; then
        # Read first 50 lines
        OUTPUT_CONTENT=$(head -n 50 "$OUTPUT_PATH" | base64 -w 0)
    elif [[ "$OUTPUT_PATH" == *.pdf ]]; then
        # Try to convert PDF to text for verification using pdftotext
        if command -v pdftotext &> /dev/null; then
            pdftotext "$OUTPUT_PATH" /tmp/pdf_content.txt
            OUTPUT_CONTENT=$(head -n 50 /tmp/pdf_content.txt | base64 -w 0)
        else
            OUTPUT_CONTENT="PDF_NO_TEXT_TOOL"
        fi
    else
        OUTPUT_CONTENT="BINARY_FORMAT"
    fi
fi

# Check if application is running
APP_RUNNING=$(pgrep -f "LobbyTrack" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_found": $OUTPUT_FOUND,
    "output_path": "$OUTPUT_PATH",
    "output_size_bytes": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "app_was_running": $APP_RUNNING,
    "file_content_base64": "$OUTPUT_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="