#!/bin/bash
echo "=== Exporting upload_account_document results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
take_screenshot /tmp/upload_account_document_final.png

# Load baseline stats
INITIAL_DOC_COUNT=$(cat /tmp/initial_doc_count.txt 2>/dev/null || echo "0")
CURRENT_DOC_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM documents WHERE deleted=0" | tr -d '[:space:]')
ORIG_PDF_SIZE=$(cat /tmp/orig_pdf_size.txt 2>/dev/null || echo "0")

# Initialize variables
DOC_FOUND="false"
D_ID=""
D_NAME=""
D_CATEGORY=""
D_STATUS=""
D_DATE=""
D_DESC=""
REV_EXISTS="false"
R_ID=""
R_FILENAME=""
LINK_EXISTS="false"
UPLOADED_FILE_SIZE="0"

# Find the Document record
DOC_DATA=$(suitecrm_db_query "SELECT id, document_name, category_id, status_id, publish_date, description FROM documents WHERE document_name='Apex NDA 2026' AND deleted=0 ORDER BY date_entered DESC LIMIT 1")

if [ -n "$DOC_DATA" ]; then
    DOC_FOUND="true"
    D_ID=$(echo "$DOC_DATA" | awk -F'\t' '{print $1}')
    D_NAME=$(echo "$DOC_DATA" | awk -F'\t' '{print $2}')
    D_CATEGORY=$(echo "$DOC_DATA" | awk -F'\t' '{print $3}')
    D_STATUS=$(echo "$DOC_DATA" | awk -F'\t' '{print $4}')
    D_DATE=$(echo "$DOC_DATA" | awk -F'\t' '{print $5}')
    D_DESC=$(echo "$DOC_DATA" | awk -F'\t' '{print $6}')

    # Find the associated Document Revision
    REV_DATA=$(suitecrm_db_query "SELECT id, filename FROM document_revisions WHERE document_id='$D_ID' AND deleted=0 ORDER BY date_entered DESC LIMIT 1")
    if [ -n "$REV_DATA" ]; then
        REV_EXISTS="true"
        R_ID=$(echo "$REV_DATA" | awk -F'\t' '{print $1}')
        R_FILENAME=$(echo "$REV_DATA" | awk -F'\t' '{print $2}')
        
        # Check if physical file exists in the upload directory inside the container
        UPLOADED_FILE_SIZE=$(docker exec suitecrm-app stat -c %s "/var/www/html/upload/$R_ID" 2>/dev/null || echo "0")
    fi

    # Find the target Account ID
    ACC_ID=$(suitecrm_db_query "SELECT id FROM accounts WHERE name='Apex Industrial Solutions' AND deleted=0 LIMIT 1")
    
    # Check if a relationship exists in the junction table
    if [ -n "$ACC_ID" ]; then
        LINK_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM documents_accounts WHERE document_id='$D_ID' AND account_id='$ACC_ID' AND deleted=0" | tr -d '[:space:]')
        if [ "$LINK_COUNT" -gt 0 ]; then
            LINK_EXISTS="true"
        fi
    fi
fi

# Build JSON structure safely
RESULT_JSON=$(cat << JSONEOF
{
  "document_found": ${DOC_FOUND},
  "document_id": "$(json_escape "${D_ID:-}")",
  "document_name": "$(json_escape "${D_NAME:-}")",
  "category": "$(json_escape "${D_CATEGORY:-}")",
  "status": "$(json_escape "${D_STATUS:-}")",
  "publish_date": "$(json_escape "${D_DATE:-}")",
  "description": "$(json_escape "${D_DESC:-}")",
  "revision_exists": ${REV_EXISTS},
  "revision_id": "$(json_escape "${R_ID:-}")",
  "filename": "$(json_escape "${R_FILENAME:-}")",
  "linked_to_account": ${LINK_EXISTS},
  "uploaded_file_size": ${UPLOADED_FILE_SIZE},
  "original_file_size": ${ORIG_PDF_SIZE},
  "initial_doc_count": ${INITIAL_DOC_COUNT},
  "current_doc_count": ${CURRENT_DOC_COUNT}
}
JSONEOF
)

# Use safe write utility from task_utils.sh
safe_write_result "/tmp/upload_account_document_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/upload_account_document_result.json"
echo "$RESULT_JSON"
echo "=== upload_account_document export complete ==="