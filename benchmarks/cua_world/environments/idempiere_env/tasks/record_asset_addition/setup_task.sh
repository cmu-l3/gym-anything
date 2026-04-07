#!/bin/bash
set -e
echo "=== Setting up record_asset_addition task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# -----------------------------------------------------------------------------
# 1. Ensure the Target Asset Exists (VAN-001)
# -----------------------------------------------------------------------------
echo "--- Preparing Asset Data ---"

# Get Client ID (GardenWorld)
CLIENT_ID=$(get_gardenworld_client_id)
if [ -z "$CLIENT_ID" ]; then
    CLIENT_ID=11
    echo "Warning: Could not determine Client ID, defaulting to 11"
fi

# Check if VAN-001 exists
ASSET_EXISTS=$(idempiere_query "SELECT COUNT(*) FROM a_asset WHERE value='VAN-001' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")

if [ "$ASSET_EXISTS" -eq "0" ]; then
    echo "Creating missing asset 'VAN-001'..."
    
    # Need an Asset Group ID. Try to find 'Vehicle' or fallback to first available.
    GROUP_ID=$(idempiere_query "SELECT a_asset_group_id FROM a_asset_group WHERE ad_client_id=$CLIENT_ID AND isactive='Y' LIMIT 1" 2>/dev/null)
    
    if [ -n "$GROUP_ID" ]; then
        # Insert the asset via SQL to ensure starting state is correct
        # Note: In a real scenario, we might use web API, but SQL is safer for setup reliability
        idempiere_query "INSERT INTO a_asset (
            a_asset_id, ad_client_id, ad_org_id, isactive, created, createdby, updated, updatedby,
            value, name, a_asset_group_id, isowned, isdisposed, isfullydepreciated, isinpossession
        ) VALUES (
            nextval('a_asset_seq'), $CLIENT_ID, 0, 'Y', now(), 100, now(), 100,
            'VAN-001', 'Company Delivery Van', $GROUP_ID, 'Y', 'N', 'N', 'Y'
        )"
        echo "Asset VAN-001 created."
    else
        echo "ERROR: No Asset Group found. Cannot create asset."
        exit 1
    fi
else
    echo "Asset VAN-001 already exists."
fi

# -----------------------------------------------------------------------------
# 2. Clean up any previous additions for this specific asset to avoid confusion
# -----------------------------------------------------------------------------
# Get the Asset ID
ASSET_ID=$(idempiere_query "SELECT a_asset_id FROM a_asset WHERE value='VAN-001' AND ad_client_id=$CLIENT_ID" 2>/dev/null)

if [ -n "$ASSET_ID" ]; then
    # We won't delete data (bad practice), but we'll record the initial count
    INITIAL_ADDITION_COUNT=$(idempiere_query "SELECT COUNT(*) FROM a_asset_addition WHERE a_asset_id=$ASSET_ID" 2>/dev/null || echo "0")
    echo "$INITIAL_ADDITION_COUNT" > /tmp/initial_addition_count.txt
    echo "Initial addition count for VAN-001: $INITIAL_ADDITION_COUNT"
else
    echo "ERROR: Failed to retrieve Asset ID for VAN-001"
    exit 1
fi

# -----------------------------------------------------------------------------
# 3. Setup Application State
# -----------------------------------------------------------------------------
echo "--- Preparing iDempiere Window ---"

# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Firefox"; then
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Navigate to Dashboard
ensure_idempiere_open ""
sleep 2

# Maximize
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -xa firefox 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="