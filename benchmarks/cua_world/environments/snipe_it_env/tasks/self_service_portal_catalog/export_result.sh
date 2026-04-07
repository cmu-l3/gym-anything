#!/bin/bash
echo "=== Exporting self_service_portal_catalog results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Helper function to get model requestable status (1 or 0)
get_model_req() {
    local val=$(snipeit_db_query "SELECT requestable FROM models WHERE name='$1' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
    if [ -z "$val" ]; then echo "0"; else echo "$val"; fi
}

# Helper function to get asset requestable status (1 or 0)
get_asset_req() {
    local val=$(snipeit_db_query "SELECT requestable FROM assets WHERE asset_tag='$1' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
    if [ -z "$val" ]; then echo "0"; else echo "$val"; fi
}

# Helper function to get asset location name
get_asset_loc() {
    local val=$(snipeit_db_query "SELECT l.name FROM assets a LEFT JOIN locations l ON a.rtd_location_id = l.id WHERE a.asset_tag='$1' AND a.deleted_at IS NULL LIMIT 1" | tr -d '\n')
    echo "$val"
}

# Query Models
REQ_DELL=$(get_model_req "Dell U2723QE Monitor")
REQ_LOGI=$(get_model_req "Logitech MX Master 3S")
REQ_MAC=$(get_model_req "Apple MacBook Pro 16 M3 Max")

# Query Assets
REQ_L1=$(get_asset_req "LOANER-T14-01")
LOC_L1=$(get_asset_loc "LOANER-T14-01")

REQ_L2=$(get_asset_req "LOANER-T14-02")
LOC_L2=$(get_asset_loc "LOANER-T14-02")

REQ_L3=$(get_asset_req "LOANER-T14-03")
LOC_L3=$(get_asset_loc "LOANER-T14-03")

REQ_E1=$(get_asset_req "EXEC-T14-01")
REQ_E2=$(get_asset_req "EXEC-T14-02")

# Build result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "models": {
    "dell_monitor": {"requestable": $REQ_DELL},
    "logi_mouse": {"requestable": $REQ_LOGI},
    "macbook_pro": {"requestable": $REQ_MAC}
  },
  "assets": {
    "LOANER-T14-01": {"requestable": $REQ_L1, "location": "$(json_escape "$LOC_L1")"},
    "LOANER-T14-02": {"requestable": $REQ_L2, "location": "$(json_escape "$LOC_L2")"},
    "LOANER-T14-03": {"requestable": $REQ_L3, "location": "$(json_escape "$LOC_L3")"},
    "EXEC-T14-01": {"requestable": $REQ_E1},
    "EXEC-T14-02": {"requestable": $REQ_E2}
  }
}
JSONEOF
)

safe_write_result "/tmp/self_service_portal_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/self_service_portal_result.json"
echo "$RESULT_JSON"
echo "=== self_service_portal_catalog export complete ==="