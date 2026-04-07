#!/bin/bash
echo "=== Exporting mobile_device_aup_enforcement results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/aup_enforcement_final.png

# 1. Gather Category Configurations
CAT_LAPTOP=$(snipeit_db_query "SELECT require_accept, eula_text FROM categories WHERE name='Laptops' AND deleted_at IS NULL LIMIT 1")
LAPTOP_REQ=$(echo "$CAT_LAPTOP" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
LAPTOP_EULA=$(echo "$CAT_LAPTOP" | awk -F'\t' '{print $2}')

CAT_TABLET=$(snipeit_db_query "SELECT require_accept, eula_text FROM categories WHERE name='Tablets' AND deleted_at IS NULL LIMIT 1")
TABLET_REQ=$(echo "$CAT_TABLET" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
TABLET_EULA=$(echo "$CAT_TABLET" | awk -F'\t' '{print $2}')

CAT_DESKTOP=$(snipeit_db_query "SELECT require_accept, eula_text FROM categories WHERE name='Desktops' AND deleted_at IS NULL LIMIT 1")
DESKTOP_REQ=$(echo "$CAT_DESKTOP" | awk -F'\t' '{print $1}' | tr -d '[:space:]')

# 2. Gather User and Asset Assignments
USER_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='dthorne' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')

LAPTOP_ASSET=$(snipeit_db_query "SELECT id, assigned_to FROM assets WHERE asset_tag='LT-2026-001' AND deleted_at IS NULL LIMIT 1")
LAPTOP_ID=$(echo "$LAPTOP_ASSET" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
LAPTOP_ASSIGNED=$(echo "$LAPTOP_ASSET" | awk -F'\t' '{print $2}' | tr -d '[:space:]')

TABLET_ASSET=$(snipeit_db_query "SELECT id, assigned_to FROM assets WHERE asset_tag='TAB-2026-001' AND deleted_at IS NULL LIMIT 1")
TABLET_ID=$(echo "$TABLET_ASSET" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
TABLET_ASSIGNED=$(echo "$TABLET_ASSET" | awk -F'\t' '{print $2}' | tr -d '[:space:]')

# 3. Gather Process Order Validation (Checkout Acceptances)
# We check if a record exists in checkout_acceptances for these assets. 
# This is only created by Snipe-IT if the category required acceptance *at the time of checkout*.
LAPTOP_ACCEPT_COUNT=0
if [ -n "$LAPTOP_ID" ] && [ -n "$USER_ID" ]; then
    LAPTOP_ACCEPT_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM checkout_acceptances WHERE checkoutable_id=${LAPTOP_ID} AND checkoutable_type='App\\\\Models\\\\Asset' AND assigned_to_id=${USER_ID}" | tr -d '[:space:]')
fi

TABLET_ACCEPT_COUNT=0
if [ -n "$TABLET_ID" ] && [ -n "$USER_ID" ]; then
    TABLET_ACCEPT_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM checkout_acceptances WHERE checkoutable_id=${TABLET_ID} AND checkoutable_type='App\\\\Models\\\\Asset' AND assigned_to_id=${USER_ID}" | tr -d '[:space:]')
fi

# Build result JSON safely
RESULT_JSON=$(cat << JSONEOF
{
  "target_user_id": "${USER_ID:-0}",
  "categories": {
    "laptops": {
      "require_accept": "${LAPTOP_REQ:-0}",
      "eula_text": "$(json_escape "$LAPTOP_EULA")"
    },
    "tablets": {
      "require_accept": "${TABLET_REQ:-0}",
      "eula_text": "$(json_escape "$TABLET_EULA")"
    },
    "desktops": {
      "require_accept": "${DESKTOP_REQ:-0}"
    }
  },
  "assets": {
    "laptop": {
      "id": "${LAPTOP_ID:-0}",
      "assigned_to": "${LAPTOP_ASSIGNED:-0}",
      "acceptance_records_count": ${LAPTOP_ACCEPT_COUNT:-0}
    },
    "tablet": {
      "id": "${TABLET_ID:-0}",
      "assigned_to": "${TABLET_ASSIGNED:-0}",
      "acceptance_records_count": ${TABLET_ACCEPT_COUNT:-0}
    }
  }
}
JSONEOF
)

safe_write_result "/tmp/mobile_device_aup_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/mobile_device_aup_result.json"
echo "$RESULT_JSON"
echo "=== mobile_device_aup_enforcement export complete ==="