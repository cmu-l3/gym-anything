#!/bin/bash
# Setup script for create_change_template task

echo "=== Setting up Create Change Template task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure SDP is running
ensure_sdp_running

# 2. Ensure Prerequisite Data Exists (Change Types, Impact, Urgency)
# We inject these if missing to ensure the agent can actually select them.
echo "Verifying/Seeding required dropdown data..."

# Check/Add 'Standard' Change Type
sdp_db_exec "INSERT INTO changetype (typeid, typename, description, colorid) 
SELECT (SELECT COALESCE(MAX(typeid),0)+1 FROM changetype), 'Standard', 'Pre-approved low risk change', 1 
WHERE NOT EXISTS (SELECT 1 FROM changetype WHERE typename='Standard');"

# Check/Add 'Low' Impact
sdp_db_exec "INSERT INTO impact (impactid, name, description) 
SELECT (SELECT COALESCE(MAX(impactid),0)+1 FROM impact), 'Low', 'Low Impact' 
WHERE NOT EXISTS (SELECT 1 FROM impact WHERE name='Low');"

# Check/Add 'Low' Urgency
sdp_db_exec "INSERT INTO urgency (urgencyid, name, description) 
SELECT (SELECT COALESCE(MAX(urgencyid),0)+1 FROM urgency), 'Low', 'Low Urgency' 
WHERE NOT EXISTS (SELECT 1 FROM urgency WHERE name='Low');"

# Check/Add 'Maintenance' Reason
# Note: Table might be reasonforchange or changereason depending on version. 
# We try reasonforchange first (common in newer SDP), then fallback.
sdp_db_exec "INSERT INTO reasonforchange (reasonid, name, description) 
SELECT (SELECT COALESCE(MAX(reasonid),0)+1 FROM reasonforchange), 'Maintenance', 'Routine Maintenance' 
WHERE NOT EXISTS (SELECT 1 FROM reasonforchange WHERE name='Maintenance');" 2>/dev/null || \
sdp_db_exec "INSERT INTO changereason (reasonid, name) 
SELECT (SELECT COALESCE(MAX(reasonid),0)+1 FROM changereason), 'Maintenance' 
WHERE NOT EXISTS (SELECT 1 FROM changereason WHERE name='Maintenance');"

# 3. Clean up any previous runs (delete template if it exists)
sdp_db_exec "DELETE FROM changetemplate WHERE templatename = 'Weekly Server Patching';"

# 4. Open Firefox to Dashboard
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"
sleep 5

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Task: Create 'Weekly Server Patching' Change Template"