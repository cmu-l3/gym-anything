#!/bin/bash
echo "=== Exporting eol_hardware_refresh_cycle results ==="

source /workspace/scripts/task_utils.sh

# Take final evidence screenshot
take_screenshot /tmp/task_final.png

# Load expected User IDs
U_ALICE=$(cat /tmp/u_alice.txt 2>/dev/null || echo "0")
U_BOB=$(cat /tmp/u_bob.txt 2>/dev/null || echo "0")
U_CHARLIE=$(cat /tmp/u_charlie.txt 2>/dev/null || echo "0")
U_DAVE=$(cat /tmp/u_dave.txt 2>/dev/null || echo "0")

# 1. Fetch Status Label details
LBL_DATA=$(snipeit_db_query "SELECT id, deployable, pending, archived FROM status_labels WHERE name='Pending E-Waste' LIMIT 1")
LBL_ID=""
LBL_DEPLOYABLE="1"
LBL_PENDING="0"
LBL_ARCHIVED="0"
if [ -n "$LBL_DATA" ]; then
    LBL_ID=$(echo "$LBL_DATA" | awk -F'\t' '{print $1}')
    LBL_DEPLOYABLE=$(echo "$LBL_DATA" | awk -F'\t' '{print $2}')
    LBL_PENDING=$(echo "$LBL_DATA" | awk -F'\t' '{print $3}')
    LBL_ARCHIVED=$(echo "$LBL_DATA" | awk -F'\t' '{print $4}')
fi

# Helper function to get an asset's final state
export_asset() {
    local tag="$1"
    local data=$(snipeit_db_query "SELECT COALESCE(assigned_to, 0), status_id FROM assets WHERE asset_tag='$tag' AND deleted_at IS NULL LIMIT 1")
    if [ -n "$data" ]; then
        local assigned=$(echo "$data" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
        local status=$(echo "$data" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
        echo "{\"tag\": \"$tag\", \"found\": true, \"assigned_to\": \"$assigned\", \"status_id\": \"$status\"}"
    else
        echo "{\"tag\": \"$tag\", \"found\": false}"
    fi
}

A_EOL01=$(export_asset "ASSET-EOL-01")
A_EOL02=$(export_asset "ASSET-EOL-02")
A_ACT01=$(export_asset "ASSET-ACT-01")
A_MON01=$(export_asset "ASSET-MON-01")

# Helper function to see what assets are checked out to a user
get_user_assets() {
    local uid="$1"
    if [ -z "$uid" ] || [ "$uid" == "0" ]; then echo "[]"; return; fi
    local tags=$(snipeit_db_query "SELECT asset_tag FROM assets WHERE assigned_to=$uid AND deleted_at IS NULL" | tr '\n' ',' | sed 's/,$//')
    if [ -z "$tags" ]; then
        echo "[]"
    else
        IFS=',' read -ra ARR <<< "$tags"
        local json="["
        local first=true
        for t in "${ARR[@]}"; do
            if [ "$first" = true ]; then first=false; else json+=","; fi
            json+="\"$t\""
        done
        json+="]"
        echo "$json"
    fi
}

ALICE_ASSETS=$(get_user_assets "$U_ALICE")
BOB_ASSETS=$(get_user_assets "$U_BOB")

# Compile JSON payload safely
RESULT_JSON=$(cat << JSONEOF
{
    "status_label": {
        "found": $(if [ -n "$LBL_ID" ]; then echo "true"; else echo "false"; fi),
        "id": "${LBL_ID}",
        "deployable": "${LBL_DEPLOYABLE}",
        "pending": "${LBL_PENDING}",
        "archived": "${LBL_ARCHIVED}"
    },
    "assets": {
        "eol_01": $A_EOL01,
        "eol_02": $A_EOL02,
        "act_01": $A_ACT01,
        "mon_01": $A_MON01
    },
    "users": {
        "alice": { "id": "${U_ALICE}", "assets": $ALICE_ASSETS },
        "bob": { "id": "${U_BOB}", "assets": $BOB_ASSETS },
        "charlie": { "id": "${U_CHARLIE}" },
        "dave": { "id": "${U_DAVE}" }
    }
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"
echo "Results written to /tmp/task_result.json"
echo "$RESULT_JSON"
echo "=== Export Complete ==="