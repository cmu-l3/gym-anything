#!/bin/bash
# Export script for Record Patient Consent task

echo "=== Exporting Record Patient Consent Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    echo "Final screenshot captured"
else
    echo "WARNING: Could not capture final screenshot"
fi

# Get initial counts
INITIAL_DOC_COUNT=$(cat /tmp/initial_doc_count.txt 2>/dev/null || echo "0")
INITIAL_ONSITE_COUNT=$(cat /tmp/initial_onsite_count.txt 2>/dev/null || echo "0")
INITIAL_FORMS_COUNT=$(cat /tmp/initial_forms_count.txt 2>/dev/null || echo "0")

# Get current counts
CURRENT_DOC_COUNT=$(openemr_query "SELECT COUNT(*) FROM documents WHERE foreign_id=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_ONSITE_COUNT=$(openemr_query "SELECT COUNT(*) FROM onsite_documents WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_FORMS_COUNT=$(openemr_query "SELECT COUNT(*) FROM forms WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")

echo "Document counts:"
echo "  documents table: initial=$INITIAL_DOC_COUNT, current=$CURRENT_DOC_COUNT"
echo "  onsite_documents: initial=$INITIAL_ONSITE_COUNT, current=$CURRENT_ONSITE_COUNT"
echo "  forms: initial=$INITIAL_FORMS_COUNT, current=$CURRENT_FORMS_COUNT"

# Check for new documents
NEW_DOC_FOUND="false"
NEW_DOC_ID=""
NEW_DOC_NAME=""
NEW_DOC_DATE=""
NEW_DOC_CATEGORY=""
NEW_DOC_TYPE=""

# Query for newest document for this patient
if [ "$CURRENT_DOC_COUNT" -gt "$INITIAL_DOC_COUNT" ]; then
    echo ""
    echo "=== New document(s) detected in documents table ==="
    
    NEWEST_DOC=$(openemr_query "SELECT d.id, d.name, d.type, d.date, c.name as category FROM documents d LEFT JOIN categories_to_documents cd ON d.id=cd.document_id LEFT JOIN categories c ON cd.category_id=c.id WHERE d.foreign_id=$PATIENT_PID ORDER BY d.id DESC LIMIT 1" 2>/dev/null)
    
    if [ -n "$NEWEST_DOC" ]; then
        NEW_DOC_FOUND="true"
        NEW_DOC_ID=$(echo "$NEWEST_DOC" | cut -f1)
        NEW_DOC_NAME=$(echo "$NEWEST_DOC" | cut -f2)
        NEW_DOC_TYPE=$(echo "$NEWEST_DOC" | cut -f3)
        NEW_DOC_DATE=$(echo "$NEWEST_DOC" | cut -f4)
        NEW_DOC_CATEGORY=$(echo "$NEWEST_DOC" | cut -f5)
        
        echo "Newest document:"
        echo "  ID: $NEW_DOC_ID"
        echo "  Name: $NEW_DOC_NAME"
        echo "  Type: $NEW_DOC_TYPE"
        echo "  Date: $NEW_DOC_DATE"
        echo "  Category: $NEW_DOC_CATEGORY"
    fi
fi

# Check onsite_documents table for portal documents
NEW_ONSITE_FOUND="false"
NEW_ONSITE_ID=""
NEW_ONSITE_NAME=""
NEW_ONSITE_DATE=""

if [ "$CURRENT_ONSITE_COUNT" -gt "$INITIAL_ONSITE_COUNT" ]; then
    echo ""
    echo "=== New document(s) detected in onsite_documents table ==="
    
    NEWEST_ONSITE=$(openemr_query "SELECT id, file_name, create_date, doc_type FROM onsite_documents WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)
    
    if [ -n "$NEWEST_ONSITE" ]; then
        NEW_ONSITE_FOUND="true"
        NEW_ONSITE_ID=$(echo "$NEWEST_ONSITE" | cut -f1)
        NEW_ONSITE_NAME=$(echo "$NEWEST_ONSITE" | cut -f2)
        NEW_ONSITE_DATE=$(echo "$NEWEST_ONSITE" | cut -f3)
        NEW_ONSITE_TYPE=$(echo "$NEWEST_ONSITE" | cut -f4)
        
        echo "Newest onsite document:"
        echo "  ID: $NEW_ONSITE_ID"
        echo "  Name: $NEW_ONSITE_NAME"
        echo "  Date: $NEW_ONSITE_DATE"
        echo "  Type: $NEW_ONSITE_TYPE"
        
        # If no regular doc found but onsite found, use onsite info
        if [ "$NEW_DOC_FOUND" = "false" ]; then
            NEW_DOC_FOUND="true"
            NEW_DOC_ID="$NEW_ONSITE_ID"
            NEW_DOC_NAME="$NEW_ONSITE_NAME"
            NEW_DOC_DATE="$NEW_ONSITE_DATE"
            NEW_DOC_TYPE="$NEW_ONSITE_TYPE"
            NEW_DOC_CATEGORY="Onsite Document"
        fi
    fi
fi

# Check forms table for new forms
NEW_FORM_FOUND="false"
NEW_FORM_ID=""
NEW_FORM_NAME=""
NEW_FORM_DATE=""

if [ "$CURRENT_FORMS_COUNT" -gt "$INITIAL_FORMS_COUNT" ]; then
    echo ""
    echo "=== New form(s) detected in forms table ==="
    
    NEWEST_FORM=$(openemr_query "SELECT id, form_name, date FROM forms WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)
    
    if [ -n "$NEWEST_FORM" ]; then
        NEW_FORM_FOUND="true"
        NEW_FORM_ID=$(echo "$NEWEST_FORM" | cut -f1)
        NEW_FORM_NAME=$(echo "$NEWEST_FORM" | cut -f2)
        NEW_FORM_DATE=$(echo "$NEWEST_FORM" | cut -f3)
        
        echo "Newest form:"
        echo "  ID: $NEW_FORM_ID"
        echo "  Name: $NEW_FORM_NAME"
        echo "  Date: $NEW_FORM_DATE"
    fi
fi

# Check if document is consent-related
IS_CONSENT_DOC="false"
DOC_NAME_LOWER=$(echo "$NEW_DOC_NAME $NEW_DOC_CATEGORY $NEW_DOC_TYPE $NEW_FORM_NAME" | tr '[:upper:]' '[:lower:]')
if echo "$DOC_NAME_LOWER" | grep -qE "(consent|authorization|agreement|permission|hipaa)"; then
    IS_CONSENT_DOC="true"
    echo "Document appears to be consent-related"
fi

# Check if document was created today
IS_TODAY="false"
TODAY=$(date +%Y-%m-%d)
if echo "$NEW_DOC_DATE" | grep -q "$TODAY"; then
    IS_TODAY="true"
    echo "Document dated today"
fi

# Escape special characters for JSON
NEW_DOC_NAME_ESCAPED=$(echo "$NEW_DOC_NAME" | sed 's/"/\\"/g' | tr '\n' ' ')
NEW_DOC_CATEGORY_ESCAPED=$(echo "$NEW_DOC_CATEGORY" | sed 's/"/\\"/g' | tr '\n' ' ')
NEW_FORM_NAME_ESCAPED=$(echo "$NEW_FORM_NAME" | sed 's/"/\\"/g' | tr '\n' ' ')

# Determine overall success indicators
ANY_NEW_DOC="false"
if [ "$NEW_DOC_FOUND" = "true" ] || [ "$NEW_FORM_FOUND" = "true" ] || [ "$NEW_ONSITE_FOUND" = "true" ]; then
    ANY_NEW_DOC="true"
fi

DOC_COUNT_INCREASED="false"
if [ "$CURRENT_DOC_COUNT" -gt "$INITIAL_DOC_COUNT" ] || \
   [ "$CURRENT_ONSITE_COUNT" -gt "$INITIAL_ONSITE_COUNT" ] || \
   [ "$CURRENT_FORMS_COUNT" -gt "$INITIAL_FORMS_COUNT" ]; then
    DOC_COUNT_INCREASED="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/consent_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "counts": {
        "documents": {
            "initial": ${INITIAL_DOC_COUNT:-0},
            "current": ${CURRENT_DOC_COUNT:-0}
        },
        "onsite_documents": {
            "initial": ${INITIAL_ONSITE_COUNT:-0},
            "current": ${CURRENT_ONSITE_COUNT:-0}
        },
        "forms": {
            "initial": ${INITIAL_FORMS_COUNT:-0},
            "current": ${CURRENT_FORMS_COUNT:-0}
        }
    },
    "document_count_increased": $DOC_COUNT_INCREASED,
    "any_new_document": $ANY_NEW_DOC,
    "new_document": {
        "found": $NEW_DOC_FOUND,
        "id": "$NEW_DOC_ID",
        "name": "$NEW_DOC_NAME_ESCAPED",
        "type": "$NEW_DOC_TYPE",
        "date": "$NEW_DOC_DATE",
        "category": "$NEW_DOC_CATEGORY_ESCAPED"
    },
    "new_form": {
        "found": $NEW_FORM_FOUND,
        "id": "$NEW_FORM_ID",
        "name": "$NEW_FORM_NAME_ESCAPED",
        "date": "$NEW_FORM_DATE"
    },
    "new_onsite_document": {
        "found": $NEW_ONSITE_FOUND,
        "id": "$NEW_ONSITE_ID",
        "name": "$NEW_ONSITE_NAME"
    },
    "validation": {
        "is_consent_related": $IS_CONSENT_DOC,
        "is_dated_today": $IS_TODAY
    },
    "screenshot_exists": $([ -f /tmp/task_final.png ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/consent_result.json 2>/dev/null || sudo rm -f /tmp/consent_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/consent_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/consent_result.json
chmod 666 /tmp/consent_result.json 2>/dev/null || sudo chmod 666 /tmp/consent_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/consent_result.json
echo ""
echo "=== Export Complete ==="