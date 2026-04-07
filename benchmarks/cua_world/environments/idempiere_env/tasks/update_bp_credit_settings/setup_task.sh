#!/bin/bash
set -e
echo "=== Setting up task: update_bp_credit_settings ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Verify iDempiere availability
echo "--- Checking iDempiere status ---"
if ! curl -k -s -o /dev/null --fail https://localhost:8443/webui/; then
    echo "Waiting for iDempiere..."
    timeout 60s bash -c 'until curl -k -s -o /dev/null https://localhost:8443/webui/; do sleep 5; done' || true
fi

# 3. Locate Target Business Partner (Seed Farm Inc.)
CLIENT_ID=$(get_gardenworld_client_id)
# Fallback to 11 (GardenWorld standard ID) if query fails
CLIENT_ID=${CLIENT_ID:-11}

echo "--- Locating Seed Farm Inc. (Client: $CLIENT_ID) ---"
BP_INFO=$(idempiere_query "SELECT c_bpartner_id, iscustomer FROM c_bpartner WHERE name='Seed Farm Inc.' AND ad_client_id=$CLIENT_ID AND isactive='Y' LIMIT 1")

if [ -z "$BP_INFO" ]; then
    echo "ERROR: 'Seed Farm Inc.' not found in database!"
    exit 1
fi

BP_ID=$(echo "$BP_INFO" | cut -d'|' -f1)
IS_CUSTOMER=$(echo "$BP_INFO" | cut -d'|' -f2)

echo "Found BP_ID: $BP_ID"

# 4. Ensure it is a Customer (so Customer tab is available)
if [ "$IS_CUSTOMER" != "Y" ]; then
    echo "Enabling IsCustomer flag..."
    idempiere_query "UPDATE c_bpartner SET iscustomer='Y' WHERE c_bpartner_id=$BP_ID"
fi

# 5. Reset values to known bad state (to ensure task is performable)
# We set them to defaults so the agent HAS to change them to pass
echo "--- Resetting credit values to default ---"
idempiere_query "UPDATE c_bpartner SET so_creditlimit=0, socreditstatus='O', paymentrule='B', updated=now() WHERE c_bpartner_id=$BP_ID"

# 6. Record Initial State for Verification
INITIAL_UPDATED_TS=$(idempiere_query "SELECT extract(epoch from updated)::bigint FROM c_bpartner WHERE c_bpartner_id=$BP_ID")

cat > /tmp/initial_bp_state.json << EOF
{
    "bp_id": $BP_ID,
    "client_id": $CLIENT_ID,
    "initial_updated_ts": ${INITIAL_UPDATED_TS:-0},
    "task_start_ts": $(cat /tmp/task_start_time.txt)
}
EOF

# 7. Prepare Browser
echo "--- Preparing Firefox ---"
# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 10
fi

# Navigate to Dashboard
ensure_idempiere_open ""

# Maximize
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="