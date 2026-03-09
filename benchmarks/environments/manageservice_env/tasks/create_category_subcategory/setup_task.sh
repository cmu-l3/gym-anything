#!/bin/bash
# Setup script for create_category_subcategory task

echo "=== Setting up Create Category/Subcategory Task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Ensure SDP is running
ensure_sdp_running

# 2. Clear mandatory password change to ensure smooth login
clear_mandatory_password_change

# 3. CLEANUP: Remove "Cloud Services" if it already exists to ensure a clean state
log "Checking for existing 'Cloud Services' category..."

# Get ID of existing category (case-insensitive)
EXISTING_ID=$(sdp_db_exec "SELECT categoryid FROM categorydefinition WHERE LOWER(name) = 'cloud services' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')

if [ -n "$EXISTING_ID" ] && [ "$EXISTING_ID" != "0" ]; then
    log "Found existing 'Cloud Services' (ID: $EXISTING_ID). Cleaning up..."
    
    # Delete subcategories first (FK constraint)
    sdp_db_exec "DELETE FROM subcategorydefinition WHERE categoryid = $EXISTING_ID;" 2>/dev/null
    
    # Delete category
    sdp_db_exec "DELETE FROM categorydefinition WHERE categoryid = $EXISTING_ID;" 2>/dev/null
    
    log "Cleanup complete."
else
    log "Clean state verified."
fi

# 4. Record initial counts
INITIAL_CAT_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM categorydefinition;" 2>/dev/null || echo "0")
echo "$INITIAL_CAT_COUNT" > /tmp/initial_cat_count.txt

# 5. Launch Firefox to Login Page
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"
sleep 5

# 6. Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="