#!/bin/bash
echo "=== Exporting warranty_audit_remediation results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/warranty_audit_final.png

# Get status label IDs
SL_PENDING_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Pending' LIMIT 1" | tr -d '[:space:]')
SL_RETIRED_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Retired' LIMIT 1" | tr -d '[:space:]')
SL_LOST_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Lost/Stolen' LIMIT 1" | tr -d '[:space:]')

# Read baseline
INITIAL_PENDING_COUNT=$(cat /tmp/warranty_initial_pending_count.txt 2>/dev/null || echo "0")

# ---------------------------------------------------------------
# Compute which assets SHOULD have been flagged
# (expired warranty = purchase_date + warranty_months < 2025-03-06)
# Exclude retired/lost assets
# ---------------------------------------------------------------
EXPECTED_EXPIRED_TAGS=$(snipeit_db_query "SELECT asset_tag FROM assets WHERE deleted_at IS NULL AND status_id NOT IN ($SL_RETIRED_ID, $SL_LOST_ID) AND warranty_months > 0 AND DATE_ADD(purchase_date, INTERVAL warranty_months MONTH) < '2025-03-06' ORDER BY asset_tag" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
echo "Expected expired tags: $EXPECTED_EXPIRED_TAGS"

# Count expected expired (excluding retired/lost)
EXPECTED_EXPIRED_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE deleted_at IS NULL AND status_id NOT IN ($SL_RETIRED_ID, $SL_LOST_ID) AND warranty_months > 0 AND DATE_ADD(purchase_date, INTERVAL warranty_months MONTH) < '2025-03-06'" 2>/dev/null | tr -d '[:space:]')

# ---------------------------------------------------------------
# Check current state of all assets
# ---------------------------------------------------------------

# Build per-asset JSON for injected warranty assets
build_asset_json() {
    local tag="$1"
    local data=$(snipeit_db_query "SELECT a.asset_tag, a.status_id, sl.name, a.notes, a.purchase_date, a.warranty_months, DATE_ADD(a.purchase_date, INTERVAL a.warranty_months MONTH) as warranty_expiry FROM assets a JOIN status_labels sl ON a.status_id = sl.id WHERE a.asset_tag='$tag' AND a.deleted_at IS NULL LIMIT 1")
    if [ -z "$data" ]; then
        echo "{\"tag\": \"$tag\", \"found\": false}"
        return
    fi
    local status_name=$(echo "$data" | awk -F'\t' '{print $3}')
    local notes=$(echo "$data" | awk -F'\t' '{print $4}')
    local purchase_date=$(echo "$data" | awk -F'\t' '{print $5}')
    local warranty_months=$(echo "$data" | awk -F'\t' '{print $6}')
    local warranty_expiry=$(echo "$data" | awk -F'\t' '{print $7}')
    echo "{\"tag\": \"$tag\", \"found\": true, \"status_name\": \"$(json_escape "$status_name")\", \"notes\": \"$(json_escape "$notes")\", \"purchase_date\": \"$purchase_date\", \"warranty_months\": \"$warranty_months\", \"warranty_expiry\": \"$warranty_expiry\"}"
}

# Get state for each injected asset
W001_JSON=$(build_asset_json "ASSET-W001")
W002_JSON=$(build_asset_json "ASSET-W002")
W003_JSON=$(build_asset_json "ASSET-W003")
W004_JSON=$(build_asset_json "ASSET-W004")
W005_JSON=$(build_asset_json "ASSET-W005")

# Check retired asset was not modified
L010_JSON=$(build_asset_json "ASSET-L010")

# Count how many assets now have Pending status
CURRENT_PENDING_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE status_id=$SL_PENDING_ID AND deleted_at IS NULL" | tr -d '[:space:]')

# Count how many assets with expired warranties now have Pending status
CORRECTLY_PENDING=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE deleted_at IS NULL AND status_id = $SL_PENDING_ID AND warranty_months > 0 AND DATE_ADD(purchase_date, INTERVAL warranty_months MONTH) < '2025-03-06'" 2>/dev/null | tr -d '[:space:]')

# Count assets with active warranties that were wrongly changed to Pending
FALSE_POSITIVES=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE deleted_at IS NULL AND status_id = $SL_PENDING_ID AND (warranty_months = 0 OR warranty_months IS NULL OR DATE_ADD(purchase_date, INTERVAL warranty_months MONTH) >= '2025-03-06')" 2>/dev/null | tr -d '[:space:]')

# Count assets with WARRANTY EXPIRED in notes
NOTE_MATCHES=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE deleted_at IS NULL AND notes LIKE '%WARRANTY EXPIRED%'" 2>/dev/null | tr -d '[:space:]')

# Check retired asset status unchanged
RETIRED_CURRENT_STATUS=$(snipeit_db_query "SELECT sl.name FROM assets a JOIN status_labels sl ON a.status_id=sl.id WHERE a.asset_tag='ASSET-L010' AND a.deleted_at IS NULL" | tr -d '\n')

# Build result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "injected_assets": {
    "W001": $W001_JSON,
    "W002": $W002_JSON,
    "W003": $W003_JSON,
    "W004": $W004_JSON,
    "W005": $W005_JSON
  },
  "retired_asset": $L010_JSON,
  "retired_current_status": "$(json_escape "$RETIRED_CURRENT_STATUS")",
  "expected_expired_count": $EXPECTED_EXPIRED_COUNT,
  "correctly_pending_count": $CORRECTLY_PENDING,
  "false_positive_count": $FALSE_POSITIVES,
  "note_match_count": $NOTE_MATCHES,
  "initial_pending_count": $INITIAL_PENDING_COUNT,
  "current_pending_count": $CURRENT_PENDING_COUNT
}
JSONEOF
)

safe_write_result "/tmp/warranty_audit_remediation_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/warranty_audit_remediation_result.json"
echo "$RESULT_JSON"
echo "=== warranty_audit_remediation export complete ==="
