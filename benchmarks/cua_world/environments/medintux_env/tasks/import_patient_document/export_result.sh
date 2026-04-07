#!/bin/bash
echo "=== Exporting import_patient_document results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PATIENT_GUID=$(cat /tmp/patient_guid.txt 2>/dev/null || echo "")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if application is running
APP_RUNNING="false"
if pgrep -f "Manager.exe" > /dev/null; then
    APP_RUNNING="true"
fi

# ============================================================
# Database Query: Check for Imported Document
# ============================================================
# We look for entries in RubriquesHead for this patient GUID
# created/modified close to today.
# MedinTux stores dates in YYYY-MM-DD format in RbDate_Date
TODAY=$(date +%Y-%m-%d)

echo "Querying database for documents linked to GUID: $PATIENT_GUID"

# Query to get the most recent document for this patient
# We fetch: Label (NomRub), Date, BlobSize (Length of data in linked blob table)
# Joined with RubriquesBlob on RbDate_PrimKey = RbBlob_PrimKey
QUERY="SELECT h.RbDate_NomRub, h.RbDate_Date, LENGTH(b.RbBlob_Data) \
       FROM RubriquesHead h \
       LEFT JOIN RubriquesBlob b ON h.RbDate_PrimKey = b.RbBlob_PrimKey \
       WHERE h.RbDate_IDDos='$PATIENT_GUID' \
       ORDER BY h.RbDate_DateCreate DESC LIMIT 1"

# Execute query (tab separated)
RESULT=$(mysql -u root DrTuxTest -N -e "$QUERY" 2>/dev/null || echo "")

DOC_FOUND="false"
DOC_LABEL=""
DOC_DATE=""
DOC_SIZE="0"

if [ -n "$RESULT" ]; then
    DOC_FOUND="true"
    DOC_LABEL=$(echo "$RESULT" | cut -f1)
    DOC_DATE=$(echo "$RESULT" | cut -f2)
    DOC_SIZE=$(echo "$RESULT" | cut -f3)
    
    # Handle NULL size
    if [ "$DOC_SIZE" == "NULL" ]; then DOC_SIZE="0"; fi
fi

echo "Found Document: $DOC_FOUND"
echo "Label: $DOC_LABEL"
echo "Date: $DOC_DATE"
echo "Size: $DOC_SIZE"

# ============================================================
# Create Result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "patient_guid": "$PATIENT_GUID",
    "document_found": $DOC_FOUND,
    "document_label": "$(echo "$DOC_LABEL" | sed 's/"/\\"/g')",
    "document_date": "$DOC_DATE",
    "document_blob_size": $DOC_SIZE,
    "expected_date": "$TODAY",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="