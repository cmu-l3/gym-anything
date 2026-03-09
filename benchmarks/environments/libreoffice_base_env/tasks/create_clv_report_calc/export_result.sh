#!/bin/bash
set -e
echo "=== Exporting create_clv_report_calc result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Documents/CLV_Report.ods"
CSV_EXPORT_PATH="/tmp/CLV_Report_Export.csv"

# 1. capture final state
take_screenshot /tmp/task_final.png

# 2. Check output file
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # 3. Convert ODS to CSV for verification (headless)
    # We copy to /tmp first to avoid locking issues if the file is open
    cp "$OUTPUT_PATH" /tmp/temp_clv_verify.ods
    
    echo "Converting ODS to CSV for verification..."
    # libreoffice headless conversion
    # Note: LibreOffice might fail if another instance is running with GUI lock.
    # We try to run it with a separate user directory to avoid lock conflicts if possible,
    # or rely on the fact that we are inside a container.
    # A safer bet is to kill the GUI instance first, but we want to preserve state for VLM if needed.
    # However, for this task, the file is saved, so closing the app is fine.
    
    kill_libreoffice
    
    su - ga -c "libreoffice --headless --convert-to csv --outdir /tmp /tmp/temp_clv_verify.ods" 2>/dev/null || true
    
    if [ -f "/tmp/temp_clv_verify.csv" ]; then
        mv "/tmp/temp_clv_verify.csv" "$CSV_EXPORT_PATH"
        echo "CSV conversion successful."
    else
        echo "WARNING: CSV conversion failed."
    fi
else
    echo "Output file not found."
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "csv_converted": $([ -f "$CSV_EXPORT_PATH" ] && echo "true" || echo "false")
}
EOF

# Move results to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

# If CSV exists, make it accessible
if [ -f "$CSV_EXPORT_PATH" ]; then
    chmod 644 "$CSV_EXPORT_PATH"
fi

echo "=== Export complete ==="