#!/bin/bash
# Export script for Upload Document task

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Load task context
DEMO_NO=$(cat /tmp/task_patient_no 2>/dev/null || echo "")
START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_doc_count 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

echo "Checking database for new documents..."

# We are looking for:
# 1. A document in 'document' table created AFTER start time
# 2. Linked in 'ctl_document' to our patient (module='demographic', module_id=DEMO_NO)

# Query to find candidate documents linked to this patient
# We join document and ctl_document
# Note: observationdate is usually DATE only in older OSCAR, updatedatetime is timestamp
# We fetch details of the most recently added document for this patient
QUERY="SELECT d.document_no, d.docdesc, d.doctype, d.docfilename, d.updatedatetime, c.module, c.module_id 
       FROM document d 
       JOIN ctl_document c ON d.document_no = c.document_no 
       WHERE c.module='demographic' 
       AND c.module_id='$DEMO_NO' 
       ORDER BY d.document_no DESC LIMIT 1"

DOC_DATA=$(oscar_query "$QUERY")

FOUND="false"
DOC_NO=""
DOC_DESC=""
DOC_TYPE=""
DOC_FILENAME=""
DOC_TIMESTAMP=""
IS_NEW="false"

if [ -n "$DOC_DATA" ]; then
    FOUND="true"
    DOC_NO=$(echo "$DOC_DATA" | cut -f1)
    DOC_DESC=$(echo "$DOC_DATA" | cut -f2)
    DOC_TYPE=$(echo "$DOC_DATA" | cut -f3)
    DOC_FILENAME=$(echo "$DOC_DATA" | cut -f4)
    DOC_TIMESTAMP=$(echo "$DOC_DATA" | cut -f5)
    
    # Check if it's actually a new document (ID higher than expected or simply created recently)
    # Simple check: Is the total count higher?
    CURRENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM ctl_document WHERE module='demographic' AND module_id='$DEMO_NO'" || echo "0")
    
    if [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
        IS_NEW="true"
    fi
    
    echo "Found Document ID: $DOC_NO"
    echo "Description: $DOC_DESC"
    echo "Type: $DOC_TYPE"
    echo "Filename: $DOC_FILENAME"
else
    echo "No documents found for patient $DEMO_NO"
fi

# Check if file exists in OSCAR's storage (inside container)
# Path varies by install, typically /usr/local/tomcat/webapps/oscar/document/ or /var/lib/oscar/document
# In the openosp docker image, it is usually /usr/local/tomcat/webapps/oscar/document/
FILE_EXISTS_ON_SERVER="false"
if [ "$FOUND" = "true" ]; then
    # OSCAR typically stores files by document_no or hashed path
    # We'll check simply if the document_no exists in the document directory structure
    # Or query the file path if stored in DB.
    # Often it's document_no.pdf or similar.
    
    # Let's check typical location in container
    if docker exec oscar-app find /usr/local/tomcat/webapps/oscar/document -name "*${DOC_FILENAME}*" | grep -q .; then
        FILE_EXISTS_ON_SERVER="true"
    elif docker exec oscar-app find /usr/local/tomcat/webapps/oscar/document -name "${DOC_NO}.*" | grep -q .; then
        FILE_EXISTS_ON_SERVER="true"
    fi
fi

# Construct JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "document_found": $FOUND,
    "is_newly_created": $IS_NEW,
    "patient_id": "$DEMO_NO",
    "document_details": {
        "id": "$DOC_NO",
        "description": "$(echo "$DOC_DESC" | sed 's/"/\\"/g')",
        "type": "$(echo "$DOC_TYPE" | sed 's/"/\\"/g')",
        "filename": "$(echo "$DOC_FILENAME" | sed 's/"/\\"/g')"
    },
    "file_exists_storage": $FILE_EXISTS_ON_SERVER,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="