#!/bin/bash
echo "=== Setting up create_vendor_record task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Record initial vendor count
INITIAL_VENDOR_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_vendor" | tr -d '[:space:]')
echo "Initial vendor count: $INITIAL_VENDOR_COUNT"
rm -f /tmp/initial_vendor_count.txt 2>/dev/null || true
echo "$INITIAL_VENDOR_COUNT" > /tmp/initial_vendor_count.txt
chmod 666 /tmp/initial_vendor_count.txt 2>/dev/null || true

# 2. Verify target vendor does not already exist (clean state)
EXISTING_IDS=$(vtiger_db_query "SELECT vendorid FROM vtiger_vendor WHERE vendorname='GreenScape Materials Co.'" 2>/dev/null | tr -d '[:space:]')
if [ -n "$EXISTING_IDS" ]; then
    echo "WARNING: Pre-existing vendor record found. Removing..."
    for VID in $EXISTING_IDS; do
        vtiger_db_query "DELETE FROM vtiger_vendoraddress WHERE vendorid=$VID" 2>/dev/null || true
        vtiger_db_query "DELETE FROM vtiger_vendorcf WHERE vendorid=$VID" 2>/dev/null || true
        vtiger_db_query "DELETE FROM vtiger_vendor WHERE vendorid=$VID" 2>/dev/null || true
        vtiger_db_query "DELETE FROM vtiger_crmentity WHERE crmid=$VID" 2>/dev/null || true
    done
fi

# 3. Update initial count after cleanup just to be safe
CLEAN_VENDOR_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_vendor" | tr -d '[:space:]')
echo "$CLEAN_VENDOR_COUNT" > /tmp/initial_vendor_count.txt

# 4. Ensure logged in and navigate to the Home dashboard
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Home&view=DashBoard"
sleep 3

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== create_vendor_record task setup complete ==="