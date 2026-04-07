#!/bin/bash
echo "=== Setting up configure_doc_sequence task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Get GardenWorld Client ID
CLIENT_ID=$(get_gardenworld_client_id)
if [ -z "$CLIENT_ID" ]; then
    CLIENT_ID=11 # Fallback to standard GardenWorld ID
fi

# 2. Record initial state of the Document Type
# We want to know what the sequence was BEFORE the task to prove it changed
INITIAL_DOCTYPE_STATE=$(idempiere_query "
    SELECT d.name, s.name 
    FROM c_doctype d 
    LEFT JOIN ad_sequence s ON d.docnosequence_id = s.ad_sequence_id 
    WHERE d.name='Purchase Order' AND d.ad_client_id=$CLIENT_ID" 2>/dev/null || echo "Unknown")

echo "Initial Document Type State: $INITIAL_DOCTYPE_STATE"
echo "$INITIAL_DOCTYPE_STATE" > /tmp/initial_doctype_state.txt

# 3. Clean up any previous attempts (delete the sequence if it exists from a failed run)
# Note: We usually don't want to delete the DocType, just reset it, but for a fresh env this shouldn't be an issue.
# If 'Purchase Order 2025' exists, we should probably warn or remove it to ensure a clean test.
EXISTING_SEQ=$(idempiere_query "SELECT ad_sequence_id FROM ad_sequence WHERE name='Purchase Order 2025' AND ad_client_id=$CLIENT_ID" 2>/dev/null)
if [ -n "$EXISTING_SEQ" ]; then
    echo "WARNING: Sequence 'Purchase Order 2025' already exists. Attempting to rename it to avoid conflict..."
    idempiere_query "UPDATE ad_sequence SET name='Purchase Order 2025 (Old)', isactive='N' WHERE ad_sequence_id=$EXISTING_SEQ"
fi

# 4. Ensure Firefox is running and ready
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to dashboard to ensure fresh state
navigate_to_dashboard

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="