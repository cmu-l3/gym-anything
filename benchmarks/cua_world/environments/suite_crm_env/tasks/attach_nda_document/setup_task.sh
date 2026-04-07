#!/bin/bash
echo "=== Setting up attach_nda_document task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Create target document
mkdir -p /home/ga/Documents
echo "Generating PDF document..."
if command -v convert >/dev/null 2>&1; then
    convert -size 800x600 xc:white -pointsize 32 -fill black \
      -draw "text 50,100 'MUTUAL NON-DISCLOSURE AGREEMENT'" \
      -draw "text 50,200 'Parties: TechFlow Solutions and SuiteCRM'" \
      -draw "text 50,300 'Effective Date: 2025-08-15'" \
      -draw "text 50,500 'Signed: [Electronically Signed]'" \
      /home/ga/Documents/signed_mnda_techflow.pdf
else
    # Fallback if imagemagick fails
    echo "MUTUAL NON-DISCLOSURE AGREEMENT - TechFlow Solutions" > /home/ga/Documents/signed_mnda_techflow.txt
    mv /home/ga/Documents/signed_mnda_techflow.txt /home/ga/Documents/signed_mnda_techflow.pdf
fi
chown ga:ga /home/ga/Documents/signed_mnda_techflow.pdf

# 2. Ensure target Account exists in CRM
echo "Ensuring target Account exists..."
ACCOUNT_EXISTS=$(suitecrm_db_query "SELECT id FROM accounts WHERE name='TechFlow Solutions' AND deleted=0 LIMIT 1")
if [ -z "$ACCOUNT_EXISTS" ]; then
    NEW_ID=$(cat /proc/sys/kernel/random/uuid)
    suitecrm_db_query "INSERT INTO accounts (id, name, date_entered, date_modified, modified_user_id, created_by, deleted) VALUES ('$NEW_ID', 'TechFlow Solutions', UTC_TIMESTAMP(), UTC_TIMESTAMP(), '1', '1', 0)"
    echo "Created Account: TechFlow Solutions"
else
    echo "Account already exists."
fi

# 3. Clean up any pre-existing notes with the exact target subject to prevent gaming
suitecrm_db_query "UPDATE notes SET deleted=1 WHERE name='Executed MNDA - TechFlow Solutions'"

# 4. Record initial note count
INITIAL_NOTE_COUNT=$(suitecrm_count "notes" "deleted=0")
echo "Initial note count: $INITIAL_NOTE_COUNT"
echo "$INITIAL_NOTE_COUNT" > /tmp/initial_note_count.txt

# 5. Ensure logged in and navigate to Notes list
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Notes&action=index"
sleep 3

# 6. Take initial screenshot
take_screenshot /tmp/attach_nda_initial.png

echo "=== attach_nda_document task setup complete ==="