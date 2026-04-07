#!/bin/bash
echo "=== Setting up upload_linked_document task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 1. Prepare the dummy PDF document
echo "Preparing dummy PDF document..."
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/Standard_NDA.pdf << 'EOF'
%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>
endobj
4 0 obj
<< /Length 61 >>
stream
BT
/F1 24 Tf
100 700 Td
(Standard Non-Disclosure Agreement) Tj
ET
endstream
endobj
5 0 obj
<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>
endobj
xref
0 6
0000000000 65535 f
0000000009 00000 n
0000000058 00000 n
0000000115 00000 n
0000000222 00000 n
0000000334 00000 n
trailer
<< /Size 6 /Root 1 0 R >>
startxref
423
%%EOF
EOF
chown ga:ga /home/ga/Documents/Standard_NDA.pdf
chmod 644 /home/ga/Documents/Standard_NDA.pdf

# 2. Cleanup existing records to prevent false positives
echo "Cleaning up any conflicting records..."
EXISTING_ORG_ID=$(vtiger_db_query "SELECT accountid FROM vtiger_account WHERE accountname='NovaTech Solutions' LIMIT 1" | tr -d '[:space:]')
if [ -n "$EXISTING_ORG_ID" ]; then
    vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid=$EXISTING_ORG_ID"
    vtiger_db_query "DELETE FROM vtiger_account WHERE accountid=$EXISTING_ORG_ID"
fi

EXISTING_DOC_ID=$(vtiger_db_query "SELECT notesid FROM vtiger_notes WHERE title='NovaTech Solutions - Signed NDA' LIMIT 1" | tr -d '[:space:]')
if [ -n "$EXISTING_DOC_ID" ]; then
    vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid=$EXISTING_DOC_ID"
    vtiger_db_query "DELETE FROM vtiger_notes WHERE notesid=$EXISTING_DOC_ID"
    vtiger_db_query "DELETE FROM vtiger_senotesrel WHERE notesid=$EXISTING_DOC_ID"
    vtiger_db_query "DELETE FROM vtiger_seattachmentsrel WHERE crmid=$EXISTING_DOC_ID"
fi

# 3. Record initial org count and document count
INITIAL_ORG_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_account" | tr -d '[:space:]')
INITIAL_DOC_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_notes" | tr -d '[:space:]')

echo "$INITIAL_ORG_COUNT" > /tmp/initial_org_count.txt
echo "$INITIAL_DOC_COUNT" > /tmp/initial_doc_count.txt

# 4. Ensure logged in and navigate to Organizations list
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Accounts&view=List"
sleep 3

# 5. Take initial screenshot
take_screenshot /tmp/upload_linked_document_initial.png

echo "=== upload_linked_document task setup complete ==="