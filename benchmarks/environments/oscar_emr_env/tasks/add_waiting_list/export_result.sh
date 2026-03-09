#!/bin/bash
# Export script for Add Waiting List task
# Collects database state and saves to JSON for verification

set -e
echo "=== Exporting Add Waiting List Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# ============================================================
# Gather Data
# ============================================================

# 1. Check for Waiting List Name
echo "Checking for 'Orthopedic Surgery' waiting list name..."
# Note: is_history='N' or NULL usually denotes active records in OSCAR
WL_NAME_DATA=$(oscar_query "SELECT ID, name FROM WaitingListName WHERE name LIKE '%Orthopedic%Surgery%' AND (is_history='N' OR is_history IS NULL) ORDER BY ID DESC LIMIT 1" 2>/dev/null || echo "")

WL_NAME_EXISTS="false"
WL_NAME_ID=""
if [ -n "$WL_NAME_DATA" ]; then
    WL_NAME_EXISTS="true"
    WL_NAME_ID=$(echo "$WL_NAME_DATA" | cut -f1)
    echo "Found WaitingListName: ID=$WL_NAME_ID"
fi

# 2. Get Patient Info
DEMO_NO=$(cat /tmp/margaret_wilson_demo_no.txt 2>/dev/null || echo "")
if [ -z "$DEMO_NO" ]; then
    # Fallback lookup
    DEMO_NO=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Margaret' AND last_name='Wilson' ORDER BY demographic_no DESC LIMIT 1" 2>/dev/null || echo "")
fi

# 3. Check for Patient on Waiting List
PATIENT_ON_LIST="false"
ON_CORRECT_LIST="false"
NOTE_CONTENT=""

if [ -n "$DEMO_NO" ]; then
    # Get the most recent waiting list entry for this patient
    # We select specific fields: listID, waiting_list_name_id, note
    ENTRY_DATA=$(oscar_query "SELECT listID, waiting_list_name_id, note FROM WaitingList WHERE demographic_no=$DEMO_NO AND (is_history='N' OR is_history IS NULL) ORDER BY listID DESC LIMIT 1" 2>/dev/null || echo "")
    
    if [ -n "$ENTRY_DATA" ]; then
        PATIENT_ON_LIST="true"
        ENTRY_LIST_ID=$(echo "$ENTRY_DATA" | cut -f2)
        NOTE_CONTENT=$(echo "$ENTRY_DATA" | cut -f3)
        
        # Check if the list ID matches our Orthopedic Surgery list
        if [ -n "$WL_NAME_ID" ] && [ "$ENTRY_LIST_ID" == "$WL_NAME_ID" ]; then
            ON_CORRECT_LIST="true"
        fi
        
        echo "Found entry for patient on list ID: $ENTRY_LIST_ID"
        echo "Note content: $NOTE_CONTENT"
    fi
fi

# 4. Anti-gaming counts
INITIAL_WL_COUNT=$(cat /tmp/initial_wl_count.txt 2>/dev/null || echo "0")
CURRENT_WL_COUNT=$(oscar_query "SELECT COUNT(*) FROM WaitingList" 2>/dev/null || echo "0")
INITIAL_WLN_COUNT=$(cat /tmp/initial_wln_count.txt 2>/dev/null || echo "0")
CURRENT_WLN_COUNT=$(oscar_query "SELECT COUNT(*) FROM WaitingListName" 2>/dev/null || echo "0")

# 5. Application State
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then APP_RUNNING="true"; fi

# ============================================================
# Create JSON Result
# ============================================================

# JSON string construction (using python to avoid escaping hell)
python3 -c "
import json
import os

result = {
    'wl_name_exists': $WL_NAME_EXISTS,
    'patient_on_list': $PATIENT_ON_LIST,
    'on_correct_list': $ON_CORRECT_LIST,
    'note_content': '''$NOTE_CONTENT''',
    'initial_wl_count': int('${INITIAL_WL_COUNT:-0}'),
    'current_wl_count': int('${CURRENT_WL_COUNT:-0}'),
    'initial_wln_count': int('${INITIAL_WLN_COUNT:-0}'),
    'current_wln_count': int('${CURRENT_WLN_COUNT:-0}'),
    'app_running': $APP_RUNNING,
    'screenshot_path': '/tmp/task_final_state.png',
    'task_start': $(cat /tmp/task_start_time.txt 2>/dev/null || echo 0)
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# Move and set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="