#!/bin/bash
# Export script for Generate Encounter Report PDF task

echo "=== Exporting Generate Encounter Report Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Configuration
OUTPUT_PATH="/home/ga/Documents/encounter_report.pdf"
PATIENT_PID=3

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final_state.png
sleep 1

# Get task timing info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

echo "Task timing: start=$TASK_START, end=$TASK_END"

# Initialize result variables
PDF_EXISTS="false"
PDF_PATH=""
PDF_SIZE=0
PDF_MTIME=0
PDF_CREATED_DURING_TASK="false"
PDF_VALID="false"
PDF_CONTAINS_PATIENT="false"
PDF_CONTAINS_ENCOUNTER="false"
PDF_TEXT=""

# Check primary expected path
echo "Checking for PDF at expected location: $OUTPUT_PATH"
if [ -f "$OUTPUT_PATH" ]; then
    PDF_EXISTS="true"
    PDF_PATH="$OUTPUT_PATH"
    echo "Found PDF at expected location"
fi

# Check alternative locations if not found
if [ "$PDF_EXISTS" = "false" ]; then
    echo "Checking alternative locations..."
    
    # Check Downloads folder
    DOWNLOADS_PDF=$(find /home/ga/Downloads -name "*.pdf" -type f 2>/dev/null | head -1)
    if [ -n "$DOWNLOADS_PDF" ]; then
        PDF_EXISTS="true"
        PDF_PATH="$DOWNLOADS_PDF"
        echo "Found PDF in Downloads: $PDF_PATH"
    fi
    
    # Check Documents folder for any PDF
    if [ "$PDF_EXISTS" = "false" ]; then
        DOCS_PDF=$(find /home/ga/Documents -name "*.pdf" -type f 2>/dev/null | head -1)
        if [ -n "$DOCS_PDF" ]; then
            PDF_EXISTS="true"
            PDF_PATH="$DOCS_PDF"
            echo "Found PDF in Documents: $PDF_PATH"
        fi
    fi
    
    # Check home folder
    if [ "$PDF_EXISTS" = "false" ]; then
        HOME_PDF=$(find /home/ga -maxdepth 1 -name "*.pdf" -type f 2>/dev/null | head -1)
        if [ -n "$HOME_PDF" ]; then
            PDF_EXISTS="true"
            PDF_PATH="$HOME_PDF"
            echo "Found PDF in home: $PDF_PATH"
        fi
    fi
    
    # Check /tmp for any recent PDFs
    if [ "$PDF_EXISTS" = "false" ]; then
        TMP_PDF=$(find /tmp -name "*.pdf" -type f -newer /tmp/task_start_time.txt 2>/dev/null | head -1)
        if [ -n "$TMP_PDF" ]; then
            PDF_EXISTS="true"
            PDF_PATH="$TMP_PDF"
            echo "Found PDF in /tmp: $PDF_PATH"
        fi
    fi
fi

# If PDF found, analyze it
if [ "$PDF_EXISTS" = "true" ] && [ -n "$PDF_PATH" ]; then
    echo "Analyzing PDF: $PDF_PATH"
    
    # Get file stats
    PDF_SIZE=$(stat -c %s "$PDF_PATH" 2>/dev/null || echo "0")
    PDF_MTIME=$(stat -c %Y "$PDF_PATH" 2>/dev/null || echo "0")
    
    echo "  Size: $PDF_SIZE bytes"
    echo "  Modification time: $PDF_MTIME"
    echo "  Task start: $TASK_START"
    
    # Check if created during task
    if [ "$PDF_MTIME" -gt "$TASK_START" ]; then
        PDF_CREATED_DURING_TASK="true"
        echo "  PDF was created/modified during task"
    else
        echo "  WARNING: PDF was NOT created during task"
    fi
    
    # Validate PDF format (check magic bytes)
    MAGIC=$(head -c 4 "$PDF_PATH" 2>/dev/null | od -c | head -1)
    if echo "$MAGIC" | grep -qE "P.*D.*F|%PDF"; then
        PDF_VALID="true"
        echo "  Valid PDF format confirmed"
    else
        echo "  WARNING: File may not be a valid PDF"
    fi
    
    # Try to extract text content for verification
    # Install pdftotext if available
    if command -v pdftotext &> /dev/null; then
        PDF_TEXT=$(pdftotext "$PDF_PATH" - 2>/dev/null | head -200)
    else
        # Try using strings as fallback
        PDF_TEXT=$(strings "$PDF_PATH" 2>/dev/null | head -100)
    fi
    
    # Check for patient name in content
    if echo "$PDF_TEXT" | grep -qi "Fadel\|Jayson"; then
        PDF_CONTAINS_PATIENT="true"
        echo "  Patient name found in PDF content"
    else
        echo "  Patient name NOT found in PDF content"
    fi
    
    # Check for encounter/medical content
    if echo "$PDF_TEXT" | grep -qiE "encounter|visit|diagnosis|patient|provider|date|medical|assessment"; then
        PDF_CONTAINS_ENCOUNTER="true"
        echo "  Medical/encounter content found in PDF"
    else
        echo "  Medical/encounter content NOT found in PDF"
    fi
    
    # Copy PDF to /tmp for verifier access
    cp "$PDF_PATH" /tmp/encounter_report_copy.pdf 2>/dev/null || true
    chmod 644 /tmp/encounter_report_copy.pdf 2>/dev/null || true
else
    echo "No PDF file found"
fi

# Save extracted text for verification
if [ -n "$PDF_TEXT" ]; then
    echo "$PDF_TEXT" > /tmp/pdf_extracted_text.txt
    chmod 644 /tmp/pdf_extracted_text.txt 2>/dev/null || true
fi

# Check if Firefox is still running
FIREFOX_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    FIREFOX_RUNNING="true"
fi

# Escape special characters in PDF path for JSON
PDF_PATH_ESCAPED=$(echo "$PDF_PATH" | sed 's/"/\\"/g')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/encounter_report_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "expected_output_path": "$OUTPUT_PATH",
    "pdf_exists": $PDF_EXISTS,
    "pdf_actual_path": "$PDF_PATH_ESCAPED",
    "pdf_size_bytes": $PDF_SIZE,
    "pdf_mtime": $PDF_MTIME,
    "pdf_created_during_task": $PDF_CREATED_DURING_TASK,
    "pdf_valid_format": $PDF_VALID,
    "pdf_contains_patient_name": $PDF_CONTAINS_PATIENT,
    "pdf_contains_encounter_data": $PDF_CONTAINS_ENCOUNTER,
    "firefox_running": $FIREFOX_RUNNING,
    "patient_pid": $PATIENT_PID,
    "screenshot_exists": $([ -f "/tmp/task_final_state.png" ] && echo "true" || echo "false"),
    "pdf_copy_path": "/tmp/encounter_report_copy.pdf",
    "pdf_text_path": "/tmp/pdf_extracted_text.txt",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/encounter_report_result.json 2>/dev/null || sudo rm -f /tmp/encounter_report_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/encounter_report_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/encounter_report_result.json
chmod 666 /tmp/encounter_report_result.json 2>/dev/null || sudo chmod 666 /tmp/encounter_report_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/encounter_report_result.json"
cat /tmp/encounter_report_result.json
echo ""
echo "=== Export Complete ==="