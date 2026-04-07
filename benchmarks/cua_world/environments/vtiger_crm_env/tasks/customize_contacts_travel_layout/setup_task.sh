#!/bin/bash
echo "=== Setting up customize_contacts_travel_layout task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Record initial schema state (max block and field IDs)
# This prevents the agent from passing by renaming existing fields/blocks
MAX_BLOCK_ID=$(vtiger_db_query "SELECT MAX(blockid) FROM vtiger_blocks" | tr -d '[:space:]' || echo "0")
MAX_FIELD_ID=$(vtiger_db_query "SELECT MAX(fieldid) FROM vtiger_field" | tr -d '[:space:]' || echo "0")

if [ -z "$MAX_BLOCK_ID" ]; then MAX_BLOCK_ID=0; fi
if [ -z "$MAX_FIELD_ID" ]; then MAX_FIELD_ID=0; fi

echo "Initial Max Block ID: $MAX_BLOCK_ID"
echo "Initial Max Field ID: $MAX_FIELD_ID"

echo "$MAX_BLOCK_ID" > /tmp/initial_max_block_id.txt
echo "$MAX_FIELD_ID" > /tmp/initial_max_field_id.txt
chmod 666 /tmp/initial_max_block_id.txt /tmp/initial_max_field_id.txt

# 2. Cleanup any previous runs just in case (idempotency)
EXISTING_BLOCK=$(vtiger_db_query "SELECT blockid FROM vtiger_blocks WHERE blocklabel='Travel Preferences' LIMIT 1" | tr -d '[:space:]')
if [ -n "$EXISTING_BLOCK" ]; then
    echo "WARNING: Block 'Travel Preferences' already exists. Removing..."
    vtiger_db_query "DELETE FROM vtiger_field WHERE block=$EXISTING_BLOCK"
    vtiger_db_query "DELETE FROM vtiger_blocks WHERE blockid=$EXISTING_BLOCK"
fi

# 3. Ensure logged in and navigate to the home dashboard
ensure_vtiger_logged_in "http://localhost:8000/"
sleep 3

# 4. Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "Task: Add custom fields to Contacts layout"
echo "Starting from Dashboard. Agent should navigate to Settings > Module Layouts & Fields."