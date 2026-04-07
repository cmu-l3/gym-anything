#!/bin/bash
echo "=== Exporting upload_linked_document results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

take_screenshot /tmp/upload_linked_document_final.png

INITIAL_ORG_COUNT=$(cat /tmp/initial_org_count.txt 2>/dev/null || echo "0")
INITIAL_DOC_COUNT=$(cat /tmp/initial_doc_count.txt 2>/dev/null || echo "0")
CURRENT_ORG_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_account" | tr -d '[:space:]')
CURRENT_DOC_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_notes" | tr -d '[:space:]')

# 1. Check if organization exists
ORG_ID=$(vtiger_db_query "SELECT accountid FROM vtiger_account WHERE accountname='NovaTech Solutions' LIMIT 1" | tr -d '[:space:]')
ORG_FOUND="false"
if [ -n "$ORG_ID" ]; then
    ORG_FOUND="true"
fi

# 2. Check if document exists
DOC_ID=$(vtiger_db_query "SELECT notesid FROM vtiger_notes WHERE title='NovaTech Solutions - Signed NDA' LIMIT 1" | tr -d '[:space:]')
DOC_FOUND="false"
if [ -n "$DOC_ID" ]; then
    DOC_FOUND="true"
fi

# 3. Check if relationship exists between them
LINKED="false"
if [ "$ORG_FOUND" = "true" ] && [ "$DOC_FOUND" = "true" ]; then
    REL_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_senotesrel WHERE crmid=$ORG_ID AND notesid=$DOC_ID" | tr -d '[:space:]')
    if [ "$REL_COUNT" -gt "0" ]; then
        LINKED="true"
    fi
fi

# 4. Check attachment record
ATTACHMENT_RECORD_FOUND="false"
ATTACHMENT_NAME=""
if [ "$DOC_FOUND" = "true" ]; then
    ATTACHMENT_ID=$(vtiger_db_query "SELECT attachmentsid FROM vtiger_seattachmentsrel WHERE crmid=$DOC_ID LIMIT 1" | tr -d '[:space:]')
    if [ -n "$ATTACHMENT_ID" ]; then
        ATTACHMENT_RECORD_FOUND="true"
        ATTACHMENT_NAME=$(vtiger_db_query "SELECT name FROM vtiger_attachments WHERE attachmentsid=$ATTACHMENT_ID LIMIT 1")
    fi
fi

# 5. Check actual storage file inside container
FILE_UPLOADED_PHYSICALLY="false"
FILE_SIZE="0"
if [ "$ATTACHMENT_RECORD_FOUND" = "true" ]; then
    # Vtiger stores files in storage/YEAR/Month/Week/attachmentsid_filename
    # Let's search inside the storage directory
    FILE_PATH_IN_CONTAINER=$(docker exec vtiger-app find /var/www/html/vtigercrm/storage/ -name "${ATTACHMENT_ID}_*" 2>/dev/null | head -1)
    if [ -n "$FILE_PATH_IN_CONTAINER" ]; then
        FILE_UPLOADED_PHYSICALLY="true"
        FILE_SIZE=$(docker exec vtiger-app stat -c %s "$FILE_PATH_IN_CONTAINER" 2>/dev/null || echo "0")
        
        # Check creation time against task start (roughly)
        FILE_MTIME=$(docker exec vtiger-app stat -c %Y "$FILE_PATH_IN_CONTAINER" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -lt "$TASK_START" ]; then
            FILE_UPLOADED_PHYSICALLY="false" # Anti-gaming: File was uploaded before task started
        fi
    fi
fi

RESULT_JSON=$(cat << JSONEOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "initial_org_count": $INITIAL_ORG_COUNT,
  "initial_doc_count": $INITIAL_DOC_COUNT,
  "current_org_count": $CURRENT_ORG_COUNT,
  "current_doc_count": $CURRENT_DOC_COUNT,
  "org_found": $ORG_FOUND,
  "doc_found": $DOC_FOUND,
  "linked": $LINKED,
  "attachment_record_found": $ATTACHMENT_RECORD_FOUND,
  "attachment_name": "$(json_escape "${ATTACHMENT_NAME:-}")",
  "file_uploaded_physically": $FILE_UPLOADED_PHYSICALLY,
  "file_size": $FILE_SIZE,
  "screenshot_path": "/tmp/upload_linked_document_final.png"
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== upload_linked_document export complete ==="