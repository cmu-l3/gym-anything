#!/bin/bash
# Export script for Create Patient Letter task
# Queries database for letter/document creation and exports results

echo "=== Exporting Create Patient Letter Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3

# Take final screenshot first
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final_state.png
sleep 1

# Get task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
echo "Task timing: start=$TASK_START, end=$TASK_END"

# Convert task start to MySQL datetime format
TASK_START_DT=$(date -d "@$TASK_START" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "1970-01-01 00:00:00")
echo "Task start datetime: $TASK_START_DT"

# Get initial counts
INITIAL_DOC_COUNT=$(cat /tmp/initial_doc_count.txt 2>/dev/null || echo "0")
INITIAL_PNOTES_COUNT=$(cat /tmp/initial_pnotes_count.txt 2>/dev/null || echo "0")
INITIAL_ONOTES_COUNT=$(cat /tmp/initial_onotes_count.txt 2>/dev/null || echo "0")
INITIAL_DICTATION_COUNT=$(cat /tmp/initial_dictation_count.txt 2>/dev/null || echo "0")

# Get current counts
CURRENT_DOC_COUNT=$(openemr_query "SELECT COUNT(*) FROM documents WHERE foreign_id=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_PNOTES_COUNT=$(openemr_query "SELECT COUNT(*) FROM pnotes WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_ONOTES_COUNT=$(openemr_query "SELECT COUNT(*) FROM onotes" 2>/dev/null || echo "0")
CURRENT_DICTATION_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_dictation" 2>/dev/null || echo "0")

echo ""
echo "Count comparison:"
echo "  Documents: initial=$INITIAL_DOC_COUNT, current=$CURRENT_DOC_COUNT"
echo "  PNotes: initial=$INITIAL_PNOTES_COUNT, current=$CURRENT_PNOTES_COUNT"
echo "  ONotes: initial=$INITIAL_ONOTES_COUNT, current=$CURRENT_ONOTES_COUNT"
echo "  Dictation: initial=$INITIAL_DICTATION_COUNT, current=$CURRENT_DICTATION_COUNT"

# Calculate new entries
NEW_DOCS=$((CURRENT_DOC_COUNT - INITIAL_DOC_COUNT))
NEW_PNOTES=$((CURRENT_PNOTES_COUNT - INITIAL_PNOTES_COUNT))
NEW_ONOTES=$((CURRENT_ONOTES_COUNT - INITIAL_ONOTES_COUNT))
NEW_DICTATION=$((CURRENT_DICTATION_COUNT - INITIAL_DICTATION_COUNT))

echo ""
echo "New entries created:"
echo "  Documents: $NEW_DOCS"
echo "  PNotes: $NEW_PNOTES"
echo "  ONotes: $NEW_ONOTES"
echo "  Dictation: $NEW_DICTATION"

# Query for recent pnotes (most likely location for letters)
echo ""
echo "=== Querying recent patient notes ==="
RECENT_PNOTES=$(openemr_query "SELECT id, date, title, body, user FROM pnotes WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 5" 2>/dev/null)
echo "Recent pnotes for patient:"
echo "$RECENT_PNOTES"

# Get the most recent pnote if new ones were created
LATEST_PNOTE_ID=""
LATEST_PNOTE_DATE=""
LATEST_PNOTE_TITLE=""
LATEST_PNOTE_BODY=""
LATEST_PNOTE_USER=""

if [ "$NEW_PNOTES" -gt 0 ]; then
    LATEST_PNOTE=$(openemr_query "SELECT id, date, title, body, user FROM pnotes WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)
    if [ -n "$LATEST_PNOTE" ]; then
        LATEST_PNOTE_ID=$(echo "$LATEST_PNOTE" | cut -f1)
        LATEST_PNOTE_DATE=$(echo "$LATEST_PNOTE" | cut -f2)
        LATEST_PNOTE_TITLE=$(echo "$LATEST_PNOTE" | cut -f3)
        LATEST_PNOTE_BODY=$(echo "$LATEST_PNOTE" | cut -f4)
        LATEST_PNOTE_USER=$(echo "$LATEST_PNOTE" | cut -f5)
        echo ""
        echo "Latest pnote details:"
        echo "  ID: $LATEST_PNOTE_ID"
        echo "  Date: $LATEST_PNOTE_DATE"
        echo "  Title: $LATEST_PNOTE_TITLE"
        echo "  Body: ${LATEST_PNOTE_BODY:0:200}..."
    fi
fi

# Query for recent documents
echo ""
echo "=== Querying recent documents ==="
RECENT_DOCS=$(openemr_query "SELECT id, date, name, type, url FROM documents WHERE foreign_id=$PATIENT_PID ORDER BY id DESC LIMIT 5" 2>/dev/null)
echo "Recent documents for patient:"
echo "$RECENT_DOCS"

# Get latest document if new ones exist
LATEST_DOC_ID=""
LATEST_DOC_DATE=""
LATEST_DOC_NAME=""
LATEST_DOC_TYPE=""

if [ "$NEW_DOCS" -gt 0 ]; then
    LATEST_DOC=$(openemr_query "SELECT id, date, name, type FROM documents WHERE foreign_id=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)
    if [ -n "$LATEST_DOC" ]; then
        LATEST_DOC_ID=$(echo "$LATEST_DOC" | cut -f1)
        LATEST_DOC_DATE=$(echo "$LATEST_DOC" | cut -f2)
        LATEST_DOC_NAME=$(echo "$LATEST_DOC" | cut -f3)
        LATEST_DOC_TYPE=$(echo "$LATEST_DOC" | cut -f4)
        echo ""
        echo "Latest document details:"
        echo "  ID: $LATEST_DOC_ID"
        echo "  Date: $LATEST_DOC_DATE"
        echo "  Name: $LATEST_DOC_NAME"
        echo "  Type: $LATEST_DOC_TYPE"
    fi
fi

# Query for recent onotes (office notes)
echo ""
echo "=== Querying recent office notes ==="
RECENT_ONOTES=$(openemr_query "SELECT id, date, body, user FROM onotes ORDER BY id DESC LIMIT 3" 2>/dev/null)
echo "Recent onotes:"
echo "$RECENT_ONOTES"

LATEST_ONOTE_BODY=""
if [ "$NEW_ONOTES" -gt 0 ]; then
    LATEST_ONOTE_BODY=$(openemr_query "SELECT body FROM onotes ORDER BY id DESC LIMIT 1" 2>/dev/null)
fi

# Check for any form entries related to letters
echo ""
echo "=== Checking form_vitals and other form tables ==="
RECENT_FORMS=$(openemr_query "SELECT form_id, form_name, date FROM forms WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 5" 2>/dev/null)
echo "Recent forms for patient:"
echo "$RECENT_FORMS"

# Determine if letter was created (any new entry counts)
LETTER_CREATED="false"
if [ "$NEW_PNOTES" -gt 0 ] || [ "$NEW_DOCS" -gt 0 ] || [ "$NEW_ONOTES" -gt 0 ] || [ "$NEW_DICTATION" -gt 0 ]; then
    LETTER_CREATED="true"
fi

# Check content for required keywords
CONTENT_HAS_LAB="false"
CONTENT_HAS_RESULT="false"
CONTENT_HAS_PHONE="false"
CONTENT_HAS_CONTACT="false"
CONTENT_HAS_JAYSON="false"

# Combine all potential content sources
ALL_CONTENT=$(echo "$LATEST_PNOTE_BODY $LATEST_PNOTE_TITLE $LATEST_ONOTE_BODY $LATEST_DOC_NAME" | tr '[:upper:]' '[:lower:]')

if echo "$ALL_CONTENT" | grep -qi "lab"; then
    CONTENT_HAS_LAB="true"
fi
if echo "$ALL_CONTENT" | grep -qi "result"; then
    CONTENT_HAS_RESULT="true"
fi
if echo "$ALL_CONTENT" | grep -qE "(555|123|4567)"; then
    CONTENT_HAS_PHONE="true"
fi
if echo "$ALL_CONTENT" | grep -qiE "(contact|call|appointment|schedule)"; then
    CONTENT_HAS_CONTACT="true"
fi
if echo "$ALL_CONTENT" | grep -qi "jayson"; then
    CONTENT_HAS_JAYSON="true"
fi

echo ""
echo "Content analysis:"
echo "  Has 'lab': $CONTENT_HAS_LAB"
echo "  Has 'result': $CONTENT_HAS_RESULT"
echo "  Has phone number: $CONTENT_HAS_PHONE"
echo "  Has contact/call/appointment: $CONTENT_HAS_CONTACT"
echo "  Has patient name: $CONTENT_HAS_JAYSON"

# Escape special characters for JSON
LATEST_PNOTE_BODY_ESCAPED=$(echo "$LATEST_PNOTE_BODY" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 500)
LATEST_PNOTE_TITLE_ESCAPED=$(echo "$LATEST_PNOTE_TITLE" | sed 's/"/\\"/g')
LATEST_DOC_NAME_ESCAPED=$(echo "$LATEST_DOC_NAME" | sed 's/"/\\"/g')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/letter_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "task_start_datetime": "$TASK_START_DT",
    "counts": {
        "initial_documents": $INITIAL_DOC_COUNT,
        "current_documents": $CURRENT_DOC_COUNT,
        "new_documents": $NEW_DOCS,
        "initial_pnotes": $INITIAL_PNOTES_COUNT,
        "current_pnotes": $CURRENT_PNOTES_COUNT,
        "new_pnotes": $NEW_PNOTES,
        "initial_onotes": $INITIAL_ONOTES_COUNT,
        "current_onotes": $CURRENT_ONOTES_COUNT,
        "new_onotes": $NEW_ONOTES,
        "initial_dictation": $INITIAL_DICTATION_COUNT,
        "current_dictation": $CURRENT_DICTATION_COUNT,
        "new_dictation": $NEW_DICTATION
    },
    "letter_created": $LETTER_CREATED,
    "latest_pnote": {
        "id": "$LATEST_PNOTE_ID",
        "date": "$LATEST_PNOTE_DATE",
        "title": "$LATEST_PNOTE_TITLE_ESCAPED",
        "body_preview": "$LATEST_PNOTE_BODY_ESCAPED",
        "user": "$LATEST_PNOTE_USER"
    },
    "latest_document": {
        "id": "$LATEST_DOC_ID",
        "date": "$LATEST_DOC_DATE",
        "name": "$LATEST_DOC_NAME_ESCAPED",
        "type": "$LATEST_DOC_TYPE"
    },
    "content_analysis": {
        "has_lab": $CONTENT_HAS_LAB,
        "has_result": $CONTENT_HAS_RESULT,
        "has_phone": $CONTENT_HAS_PHONE,
        "has_contact": $CONTENT_HAS_CONTACT,
        "has_patient_name": $CONTENT_HAS_JAYSON
    },
    "screenshot_exists": $([ -f "/tmp/task_final_state.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result JSON
rm -f /tmp/create_letter_result.json 2>/dev/null || sudo rm -f /tmp/create_letter_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/create_letter_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/create_letter_result.json
chmod 666 /tmp/create_letter_result.json 2>/dev/null || sudo chmod 666 /tmp/create_letter_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/create_letter_result.json"
cat /tmp/create_letter_result.json
echo ""
echo "=== Export Complete ==="