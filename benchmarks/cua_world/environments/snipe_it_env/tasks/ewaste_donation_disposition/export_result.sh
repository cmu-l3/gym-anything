#!/bin/bash
echo "=== Exporting ewaste_donation_disposition results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/ewaste_final.png

# ---------------------------------------------------------------
# Check Status Labels
# ---------------------------------------------------------------
LBL_EWASTE=$(snipeit_db_query "SELECT id, deployable, pending, archived FROM status_labels WHERE name='Pending E-Waste' AND deleted_at IS NULL LIMIT 1")
LBL_DONATED=$(snipeit_db_query "SELECT id, deployable, pending, archived FROM status_labels WHERE name='Donated' AND deleted_at IS NULL LIMIT 1")

EWASTE_FOUND="false"
EWASTE_ID="0"
EWASTE_DEP="0"
EWASTE_PEND="0"
EWASTE_ARCH="0"

if [ -n "$LBL_EWASTE" ]; then
    EWASTE_FOUND="true"
    EWASTE_ID=$(echo "$LBL_EWASTE" | awk -F'\t' '{print $1}')
    EWASTE_DEP=$(echo "$LBL_EWASTE" | awk -F'\t' '{print $2}')
    EWASTE_PEND=$(echo "$LBL_EWASTE" | awk -F'\t' '{print $3}')
    EWASTE_ARCH=$(echo "$LBL_EWASTE" | awk -F'\t' '{print $4}')
fi

DONATED_FOUND="false"
DONATED_ID="0"
DONATED_DEP="0"
DONATED_PEND="0"
DONATED_ARCH="0"

if [ -n "$LBL_DONATED" ]; then
    DONATED_FOUND="true"
    DONATED_ID=$(echo "$LBL_DONATED" | awk -F'\t' '{print $1}')
    DONATED_DEP=$(echo "$LBL_DONATED" | awk -F'\t' '{print $2}')
    DONATED_PEND=$(echo "$LBL_DONATED" | awk -F'\t' '{print $3}')
    DONATED_ARCH=$(echo "$LBL_DONATED" | awk -F'\t' '{print $4}')
fi

# ---------------------------------------------------------------
# Check Assets Helper
# ---------------------------------------------------------------
build_asset_json() {
    local tag="$1"
    local data=$(snipeit_db_query "SELECT a.status_id, sl.name, a.notes, a.updated_at FROM assets a LEFT JOIN status_labels sl ON a.status_id=sl.id WHERE a.asset_tag='$tag' AND a.deleted_at IS NULL LIMIT 1")
    if [ -z "$data" ]; then
        echo "{\"tag\": \"$tag\", \"found\": false}"
        return
    fi
    local status_id=$(echo "$data" | awk -F'\t' '{print $1}')
    local status_name=$(echo "$data" | awk -F'\t' '{print $2}')
    local notes=$(echo "$data" | awk -F'\t' '{print $3}')
    local updated_at=$(echo "$data" | awk -F'\t' '{print $4}')
    echo "{\"tag\": \"$tag\", \"found\": true, \"status_name\": \"$(json_escape "$status_name")\", \"notes\": \"$(json_escape "$notes")\", \"updated_at\": \"$updated_at\"}"
}

# ---------------------------------------------------------------
# Build Arrays
# ---------------------------------------------------------------
LAPTOP_JSON="["
for tag in "LT-RET-01" "LT-RET-02" "LT-RET-03" "LT-RET-04"; do
    [ "$LAPTOP_JSON" != "[" ] && LAPTOP_JSON+=","
    LAPTOP_JSON+=$(build_asset_json "$tag")
done
LAPTOP_JSON+="]"

TABLET_JSON="["
for tag in "TAB-RET-01" "TAB-RET-02" "TAB-RET-03"; do
    [ "$TABLET_JSON" != "[" ] && TABLET_JSON+=","
    TABLET_JSON+=$(build_asset_json "$tag")
done
TABLET_JSON+="]"

PRINTER_JSON="["
for tag in "PRN-RET-01" "PRN-RET-02"; do
    [ "$PRINTER_JSON" != "[" ] && PRINTER_JSON+=","
    PRINTER_JSON+=$(build_asset_json "$tag")
done
PRINTER_JSON+="]"

ACTIVE_JSON="["
for tag in "LT-ACT-01" "TAB-ACT-01"; do
    [ "$ACTIVE_JSON" != "[" ] && ACTIVE_JSON+=","
    ACTIVE_JSON+=$(build_asset_json "$tag")
done
ACTIVE_JSON+="]"

# ---------------------------------------------------------------
# Write output
# ---------------------------------------------------------------
RESULT_JSON=$(cat << JSONEOF
{
  "labels": {
    "ewaste": {
      "found": $EWASTE_FOUND,
      "deployable": "$EWASTE_DEP",
      "pending": "$EWASTE_PEND",
      "archived": "$EWASTE_ARCH"
    },
    "donated": {
      "found": $DONATED_FOUND,
      "deployable": "$DONATED_DEP",
      "pending": "$DONATED_PEND",
      "archived": "$DONATED_ARCH"
    }
  },
  "laptops": $LAPTOP_JSON,
  "tablets": $TABLET_JSON,
  "printers": $PRINTER_JSON,
  "active_assets": $ACTIVE_JSON
}
JSONEOF
)

safe_write_result "/tmp/ewaste_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/ewaste_result.json"
echo "$RESULT_JSON"
echo "=== ewaste_donation_disposition export complete ==="