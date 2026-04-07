#!/bin/bash
set -e
echo "=== Setting up create_document_type task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up potential leftovers from previous runs to ensure a clean state
# We deactivate old records with the specific names so the agent creates new ones
echo "--- Cleaning up previous runs ---"
CLIENT_ID=$(get_gardenworld_client_id)

# Deactivate existing Sequence
idempiere_query "UPDATE ad_sequence SET isactive='N', name=name||'_OLD_'||to_char(now(),'YYYYMMDDHHMISS') WHERE name='Web_Sales_Seq_2025' AND ad_client_id=$CLIENT_ID" 2>/dev/null || true

# Deactivate existing Document Type
idempiere_query "UPDATE c_doctype SET isactive='N', name=name||'_OLD_'||to_char(now(),'YYYYMMDDHHMISS') WHERE name='Web Standard Order' AND ad_client_id=$CLIENT_ID" 2>/dev/null || true

# 2. Record initial counts
INITIAL_SEQ_COUNT=$(idempiere_query "SELECT COUNT(*) FROM ad_sequence WHERE ad_client_id=$CLIENT_ID AND isactive='Y'" 2>/dev/null || echo "0")
INITIAL_DT_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_doctype WHERE ad_client_id=$CLIENT_ID AND isactive='Y'" 2>/dev/null || echo "0")

echo "$INITIAL_SEQ_COUNT" > /tmp/initial_seq_count.txt
echo "$INITIAL_DT_COUNT" > /tmp/initial_dt_count.txt

# 3. Ensure iDempiere is running and Firefox is open
echo "--- Checking iDempiere status ---"
navigate_to_dashboard

# 4. Maximize window for visibility
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 5. Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="