#!/bin/bash
# Export script for Upload Patient Photo task
# Collects verification data for the verifier

echo "=== Exporting Upload Patient Photo Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot immediately
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Get initial state for comparison
INITIAL_DOC_COUNT=$(cat /tmp/initial_doc_count.txt 2>/dev/null || echo "0")
INITIAL_PHOTO=$(cat /tmp/initial_photo_state.txt 2>/dev/null || echo "")

# Query current document count for patient
CURRENT_DOC_COUNT=$(openemr_query "SELECT COUNT(*) FROM documents WHERE foreign_id=$PATIENT_PID" 2>/dev/null || echo "0")
echo "Document count: initial=$INITIAL_DOC_COUNT, current=$CURRENT_DOC_COUNT"

# Check if patient_data photo field was updated
CURRENT_PHOTO=$(openemr_query "SELECT COALESCE(photo,'') FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null || echo "")
echo "Photo field: initial='$INITIAL_PHOTO', current='$CURRENT_PHOTO'"

# Check for new documents linked to patient
echo ""
echo "=== Checking for new documents ==="
NEW_DOCS=$(openemr_query "SELECT d.id, d.url, d.type, d.mimetype, UNIX_TIMESTAMP(d.date) as created_ts FROM documents d WHERE d.foreign_id=$PATIENT_PID ORDER BY d.id DESC LIMIT 10" 2>/dev/null)
echo "Recent documents for patient:"
echo "$NEW_DOCS"

# Parse newest document info
DOC_FOUND="false"
DOC_ID=""
DOC_URL=""
DOC_TYPE=""
DOC_MIMETYPE=""
DOC_TIMESTAMP="0"

if [ -n "$NEW_DOCS" ]; then
    # Get the first (newest) document
    FIRST_DOC=$(echo "$NEW_DOCS" | head -1)
    if [ -n "$FIRST_DOC" ]; then
        DOC_ID=$(echo "$FIRST_DOC" | cut -f1)
        DOC_URL=$(echo "$FIRST_DOC" | cut -f2)
        DOC_TYPE=$(echo "$FIRST_DOC" | cut -f3)
        DOC_MIMETYPE=$(echo "$FIRST_DOC" | cut -f4)
        DOC_TIMESTAMP=$(echo "$FIRST_DOC" | cut -f5)
        
        if [ -n "$DOC_ID" ] && [ "$DOC_ID" != "NULL" ]; then
            DOC_FOUND="true"
            echo "Newest document: ID=$DOC_ID, URL=$DOC_URL, Type=$DOC_TYPE, Mime=$DOC_MIMETYPE"
        fi
    fi
fi

# Check if document was created during task window
DOC_CREATED_DURING_TASK="false"
if [ "$DOC_FOUND" = "true" ] && [ -n "$DOC_TIMESTAMP" ] && [ "$DOC_TIMESTAMP" != "NULL" ]; then
    if [ "$DOC_TIMESTAMP" -ge "$TASK_START" ]; then
        DOC_CREATED_DURING_TASK="true"
        echo "Document created during task (timestamp: $DOC_TIMESTAMP >= $TASK_START)"
    else
        echo "Document existed before task (timestamp: $DOC_TIMESTAMP < $TASK_START)"
    fi
fi

# Check for new image files in OpenEMR documents directory
echo ""
echo "=== Checking for new image files ==="
NEW_IMAGE_FILES=""
NEW_IMAGE_COUNT=0
if [ -f /tmp/initial_image_files.txt ]; then
    # Find image files newer than task start
    find /var/www/html/openemr/sites/default/documents -type f \
        \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.gif" \) \
        -newer /tmp/task_start_time.txt 2>/dev/null > /tmp/new_image_files.txt || true
    
    if [ -f /tmp/new_image_files.txt ]; then
        NEW_IMAGE_COUNT=$(wc -l < /tmp/new_image_files.txt 2>/dev/null || echo "0")
        NEW_IMAGE_FILES=$(cat /tmp/new_image_files.txt 2>/dev/null | head -5 | tr '\n' ' ')
    fi
fi
echo "New image files found: $NEW_IMAGE_COUNT"
if [ -n "$NEW_IMAGE_FILES" ]; then
    echo "New files: $NEW_IMAGE_FILES"
fi

# Check if photo field changed
PHOTO_FIELD_CHANGED="false"
if [ "$CURRENT_PHOTO" != "$INITIAL_PHOTO" ] && [ -n "$CURRENT_PHOTO" ]; then
    PHOTO_FIELD_CHANGED="true"
    echo "Photo field changed: '$INITIAL_PHOTO' -> '$CURRENT_PHOTO'"
fi

# Determine if any photo was uploaded
PHOTO_UPLOADED="false"
if [ "$DOC_CREATED_DURING_TASK" = "true" ] || [ "$PHOTO_FIELD_CHANGED" = "true" ] || [ "$NEW_IMAGE_COUNT" -gt 0 ]; then
    PHOTO_UPLOADED="true"
fi

# Check if Firefox is still running
FIREFOX_RUNNING="false"
if pgrep -f firefox > /dev/null 2>&1; then
    FIREFOX_RUNNING="true"
fi

# Escape special characters for JSON
DOC_URL_ESCAPED=$(echo "$DOC_URL" | sed 's/"/\\"/g' | tr -d '\n')
DOC_TYPE_ESCAPED=$(echo "$DOC_TYPE" | sed 's/"/\\"/g' | tr -d '\n')
NEW_IMAGE_FILES_ESCAPED=$(echo "$NEW_IMAGE_FILES" | sed 's/"/\\"/g' | tr -d '\n')
CURRENT_PHOTO_ESCAPED=$(echo "$CURRENT_PHOTO" | sed 's/"/\\"/g' | tr -d '\n')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/upload_photo_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "patient_name": "$PATIENT_NAME",
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_doc_count": ${INITIAL_DOC_COUNT:-0},
    "current_doc_count": ${CURRENT_DOC_COUNT:-0},
    "document_found": $DOC_FOUND,
    "document": {
        "id": "$DOC_ID",
        "url": "$DOC_URL_ESCAPED",
        "type": "$DOC_TYPE_ESCAPED",
        "mimetype": "$DOC_MIMETYPE",
        "timestamp": "${DOC_TIMESTAMP:-0}"
    },
    "doc_created_during_task": $DOC_CREATED_DURING_TASK,
    "photo_field_changed": $PHOTO_FIELD_CHANGED,
    "current_photo_field": "$CURRENT_PHOTO_ESCAPED",
    "new_image_file_count": $NEW_IMAGE_COUNT,
    "new_image_files": "$NEW_IMAGE_FILES_ESCAPED",
    "photo_uploaded": $PHOTO_UPLOADED,
    "firefox_running": $FIREFOX_RUNNING,
    "screenshot_exists": $([ -f "/tmp/task_final_state.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/upload_patient_photo_result.json 2>/dev/null || sudo rm -f /tmp/upload_patient_photo_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/upload_patient_photo_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/upload_patient_photo_result.json
chmod 666 /tmp/upload_patient_photo_result.json 2>/dev/null || sudo chmod 666 /tmp/upload_patient_photo_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/upload_patient_photo_result.json
echo ""
echo "=== Export Complete ==="