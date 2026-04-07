#!/bin/bash
set -e
echo "=== Exporting AAV2 ITR Mapping result ==="

# Record end state
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/UGENE_Data/aav2_results"
GB_FILE="${RESULTS_DIR}/aav2_annotated.gb"
REPORT_FILE="${RESULTS_DIR}/itr_report.txt"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# --- Check GenBank File ---
GB_EXISTS=false
GB_VALID=false
GB_CREATED_DURING_TASK=false
ANNOTATIONS_PRESENT=false
ANNOTATION_COORDS="[]"

if [ -f "$GB_FILE" ]; then
    GB_EXISTS=true
    # Check if created/modified during task
    GB_MTIME=$(stat -c %Y "$GB_FILE" 2>/dev/null || echo "0")
    if [ "$GB_MTIME" -gt "$TASK_START" ]; then
        GB_CREATED_DURING_TASK=true
    fi
    
    # Check valid GenBank basic structure
    if head -n 5 "$GB_FILE" | grep -q "^LOCUS" && grep -q "^FEATURES" "$GB_FILE" && grep -q "^ORIGIN" "$GB_FILE"; then
        GB_VALID=true
    fi
    
    # Extract feature coordinates (ignoring standard 'source' feature)
    # Looking for lines like: "     misc_feature    1..145" or "     ITR             complement(4535..4679)"
    RAW_COORDS=$(grep -P "^     [a-zA-Z0-9_]+" "$GB_FILE" | grep -v "source" | grep -oP "\d+\.\.\d+")
    if [ -n "$RAW_COORDS" ]; then
        ANNOTATIONS_PRESENT=true
        # Format as JSON array of strings
        ANNOTATION_COORDS=$(echo "$RAW_COORDS" | awk 'BEGIN{printf "["} {if(NR>1)printf ","; printf "\"%s\"", $1} END{printf "]"}')
    fi
fi

# --- Check Report File ---
REPORT_EXISTS=false
REPORT_CREATED_DURING_TASK=false
REPORT_CONTENT=""

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS=true
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK=true
    fi
    # Grab the first 500 characters of the report and strip newlines/quotes to make it JSON safe
    REPORT_CONTENT=$(head -c 500 "$REPORT_FILE" | tr '\n' ' ' | sed 's/"/\\"/g' || true)
fi

# App running state
APP_RUNNING=false
if pgrep -f "ugene" > /dev/null; then
    APP_RUNNING=true
fi

# --- Create JSON result ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "gb_exists": $GB_EXISTS,
    "gb_valid": $GB_VALID,
    "gb_created_during_task": $GB_CREATED_DURING_TASK,
    "annotations_present": $ANNOTATIONS_PRESENT,
    "annotation_coords": $ANNOTATION_COORDS,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content": "$REPORT_CONTENT"
}
EOF

# Move to standard location with safe permissions
rm -f /tmp/aav2_itr_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/aav2_itr_result.json
chmod 666 /tmp/aav2_itr_result.json
rm -f "$TEMP_JSON"

echo "Export completed successfully to /tmp/aav2_itr_result.json."
cat /tmp/aav2_itr_result.json