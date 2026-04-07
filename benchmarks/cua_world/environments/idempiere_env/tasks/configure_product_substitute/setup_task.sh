#!/bin/bash
set -e
echo "=== Setting up configure_product_substitute task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Get GardenWorld Client ID
CLIENT_ID=$(get_gardenworld_client_id)
if [ -z "$CLIENT_ID" ]; then
    echo "ERROR: Could not find GardenWorld client ID"
    exit 1
fi

# 2. Verify Products Exist (Spade and Hoe)
echo "--- Verifying products exist ---"
SPADE_ID=$(idempiere_query "SELECT m_product_id FROM m_product WHERE name='Spade' AND ad_client_id=$CLIENT_ID" 2>/dev/null)
HOE_ID=$(idempiere_query "SELECT m_product_id FROM m_product WHERE name='Hoe' AND ad_client_id=$CLIENT_ID" 2>/dev/null)

if [ -z "$SPADE_ID" ] || [ -z "$HOE_ID" ]; then
    echo "ERROR: Required products (Spade or Hoe) not found in GardenWorld demo data."
    echo "Spade ID: $SPADE_ID, Hoe ID: $HOE_ID"
    # Fallback logic could go here, but these are standard demo data
    exit 1
fi
echo "Products found: Spade ($SPADE_ID), Hoe ($HOE_ID)"

# 3. Clean up any existing substitution between these two to ensure clean state
echo "--- Cleaning up existing substitutes ---"
idempiere_query "DELETE FROM m_substitute WHERE m_product_id=$SPADE_ID AND substitute_id=$HOE_ID" 2>/dev/null || true

# 4. Launch Firefox and Login
echo "--- Launching Application ---"
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla"; then
            break
        fi
        sleep 1
    done
fi

# Navigate to dashboard
navigate_to_dashboard

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="