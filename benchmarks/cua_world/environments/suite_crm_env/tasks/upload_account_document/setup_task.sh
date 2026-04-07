#!/bin/bash
echo "=== Setting up upload_account_document task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 1. Create the dummy PDF file in the agent's Documents folder
mkdir -p /home/ga/Documents
# Use ImageMagick to create a valid, non-empty PDF file
convert -size 600x800 xc:white -pointsize 24 -fill black -draw "text 50,50 'Mutual Non-Disclosure Agreement'" -draw "text 50,100 'Between Apex Industrial Solutions and Company'" /home/ga/Documents/Apex_NDA_Signed.pdf 2>/dev/null || \
  # Fallback if convert fails: create a text file disguised as PDF (SuiteCRM still accepts it for upload)
  echo "Mutual Non-Disclosure Agreement for Apex Industrial Solutions" > /home/ga/Documents/Apex_NDA_Signed.pdf

chown ga:ga /home/ga/Documents/Apex_NDA_Signed.pdf
chmod 644 /home/ga/Documents/Apex_NDA_Signed.pdf

# Record original file size
ORIG_SIZE=$(stat -c %s /home/ga/Documents/Apex_NDA_Signed.pdf 2>/dev/null || echo "0")
echo "$ORIG_SIZE" > /tmp/orig_pdf_size.txt

# 2. Ensure target Account exists in the database
ACC_EXISTS=$(suitecrm_db_query "SELECT COUNT(*) FROM accounts WHERE name='Apex Industrial Solutions' AND deleted=0" | tr -d '[:space:]')
if [ "$ACC_EXISTS" -eq 0 ]; then
    echo "Creating 'Apex Industrial Solutions' account..."
    # Generate UUID
    ACC_ID=$(cat /proc/sys/kernel/random/uuid)
    suitecrm_db_query "INSERT INTO accounts (id, name, date_entered, date_modified, modified_user_id, created_by, deleted) VALUES ('$ACC_ID', 'Apex Industrial Solutions', NOW(), NOW(), '1', '1', 0);"
fi

# 3. Record initial document count for anti-gaming
INITIAL_DOC_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM documents WHERE deleted=0" | tr -d '[:space:]')
echo "$INITIAL_DOC_COUNT" > /tmp/initial_doc_count.txt

# 4. Remove any pre-existing document with the target name
suitecrm_db_query "UPDATE documents SET deleted=1 WHERE document_name='Apex NDA 2026'"

# 5. Login to SuiteCRM and navigate to the Accounts list
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Accounts&action=index"
sleep 3

# 6. Take initial screenshot
take_screenshot /tmp/upload_account_document_initial.png

echo "=== upload_account_document task setup complete ==="
echo "PDF created at ~/Documents/Apex_NDA_Signed.pdf (Size: $ORIG_SIZE bytes)"
echo "Account 'Apex Industrial Solutions' is ready."