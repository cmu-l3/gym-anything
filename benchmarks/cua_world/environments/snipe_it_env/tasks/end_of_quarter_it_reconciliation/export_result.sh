#!/bin/bash
echo "=== Exporting end_of_quarter_it_reconciliation results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/recon_final.png

# ---------------------------------------------------------------
# Read baseline IDs from setup
# ---------------------------------------------------------------
ALEE_ID=$(cat /tmp/recon_alee_id.txt 2>/dev/null || echo "0")
BKUMAR_ID=$(cat /tmp/recon_bkumar_id.txt 2>/dev/null || echo "0")
DMILLER_ID=$(cat /tmp/recon_dmiller_id.txt 2>/dev/null || echo "0")
EZHANG_ID=$(cat /tmp/recon_ezhang_id.txt 2>/dev/null || echo "0")
FSINGH_ID=$(cat /tmp/recon_fsingh_id.txt 2>/dev/null || echo "0")
GPARK_ID=$(cat /tmp/recon_gpark_id.txt 2>/dev/null || echo "0")
PPATEL_ID=$(cat /tmp/recon_ppatel_id.txt 2>/dev/null || echo "0")
PPATEL_ORIG_LOC=$(cat /tmp/recon_ppatel_orig_loc.txt 2>/dev/null || echo "0")

RECON_L001_ID=$(cat /tmp/recon_l001_id.txt 2>/dev/null || echo "0")
RECON_MONA_ID=$(cat /tmp/recon_mona_id.txt 2>/dev/null || echo "0")
RECON_L002_ID=$(cat /tmp/recon_l002_id.txt 2>/dev/null || echo "0")
RECON_L003_ID=$(cat /tmp/recon_l003_id.txt 2>/dev/null || echo "0")
RECON_L004_ID=$(cat /tmp/recon_l004_id.txt 2>/dev/null || echo "0")
RECON_L005_ID=$(cat /tmp/recon_l005_id.txt 2>/dev/null || echo "0")
RECON_L006_ID=$(cat /tmp/recon_l006_id.txt 2>/dev/null || echo "0")
RECON_S001_ID=$(cat /tmp/recon_s001_id.txt 2>/dev/null || echo "0")
RECON_S002_ID=$(cat /tmp/recon_s002_id.txt 2>/dev/null || echo "0")
RECON_D001_ID=$(cat /tmp/recon_d001_id.txt 2>/dev/null || echo "0")
RECON_MONB_ID=$(cat /tmp/recon_monb_id.txt 2>/dev/null || echo "0")

MS365_ID=$(cat /tmp/recon_ms365_id.txt 2>/dev/null || echo "0")
SL_READY_ID=$(cat /tmp/recon_sl_ready_id.txt 2>/dev/null || echo "0")
SL_REPAIR_ID=$(cat /tmp/recon_sl_repair_id.txt 2>/dev/null || echo "0")
DEPT_MARKETING_ID=$(cat /tmp/recon_dept_marketing_id.txt 2>/dev/null || echo "0")

# ---------------------------------------------------------------
# Helper: build asset state JSON
# ---------------------------------------------------------------
build_asset_json() {
    local tag="$1"
    local asset_id="$2"
    local data=$(snipeit_db_query "SELECT a.asset_tag, a.status_id, sl.name, a.assigned_to, a.notes FROM assets a JOIN status_labels sl ON a.status_id=sl.id WHERE a.id=$asset_id AND a.deleted_at IS NULL LIMIT 1")
    if [ -z "$data" ]; then
        echo "{\"tag\": \"$tag\", \"found\": false}"
        return
    fi
    local status_name=$(echo "$data" | awk -F'\t' '{print $3}')
    local assigned_to=$(echo "$data" | awk -F'\t' '{print $4}' | tr -d '[:space:]')
    local notes=$(echo "$data" | awk -F'\t' '{print $5}')

    local is_checked_in="true"
    if [ -n "$assigned_to" ] && [ "$assigned_to" != "NULL" ] && [ "$assigned_to" != "0" ]; then
        is_checked_in="false"
    fi

    echo "{\"tag\": \"$tag\", \"found\": true, \"status_name\": \"$(json_escape "$status_name")\", \"is_checked_in\": $is_checked_in, \"assigned_to\": \"$assigned_to\", \"notes\": \"$(json_escape "$notes")\"}"
}

# ---------------------------------------------------------------
# Phase 1: Departing employees' hardware and user state
# ---------------------------------------------------------------
echo "  Checking Phase 1 (departures)..."

# Asset states
L001_JSON=$(build_asset_json "RECON-L001" "$RECON_L001_ID")
MONA_JSON=$(build_asset_json "RECON-MON-A" "$RECON_MONA_ID")
L002_JSON=$(build_asset_json "RECON-L002" "$RECON_L002_ID")

# User activation state
ALEE_ACTIVE=$(snipeit_db_query "SELECT activated FROM users WHERE id=$ALEE_ID AND deleted_at IS NULL" | tr -d '[:space:]')
ALEE_DEACTIVATED="false"
if [ "$ALEE_ACTIVE" = "0" ]; then
    ALEE_DEACTIVATED="true"
fi
# Check if user was soft-deleted instead
ALEE_DELETED=$(snipeit_db_query "SELECT COUNT(*) FROM users WHERE id=$ALEE_ID AND deleted_at IS NOT NULL" | tr -d '[:space:]')
if [ "$ALEE_DELETED" -gt 0 ]; then
    ALEE_DEACTIVATED="true"
fi

BKUMAR_ACTIVE=$(snipeit_db_query "SELECT activated FROM users WHERE id=$BKUMAR_ID AND deleted_at IS NULL" | tr -d '[:space:]')
BKUMAR_DEACTIVATED="false"
if [ "$BKUMAR_ACTIVE" = "0" ]; then
    BKUMAR_DEACTIVATED="true"
fi
BKUMAR_DELETED=$(snipeit_db_query "SELECT COUNT(*) FROM users WHERE id=$BKUMAR_ID AND deleted_at IS NOT NULL" | tr -d '[:space:]')
if [ "$BKUMAR_DELETED" -gt 0 ]; then
    BKUMAR_DEACTIVATED="true"
fi

# M365 seat state for departing users
ALEE_HAS_SEAT="false"
ALEE_SEAT_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM license_seats WHERE license_id=$MS365_ID AND assigned_to=$ALEE_ID AND deleted_at IS NULL" | tr -d '[:space:]')
if [ "$ALEE_SEAT_COUNT" -gt 0 ]; then
    ALEE_HAS_SEAT="true"
fi

BKUMAR_HAS_SEAT="false"
BKUMAR_SEAT_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM license_seats WHERE license_id=$MS365_ID AND assigned_to=$BKUMAR_ID AND deleted_at IS NULL" | tr -d '[:space:]')
if [ "$BKUMAR_SEAT_COUNT" -gt 0 ]; then
    BKUMAR_HAS_SEAT="true"
fi

# ---------------------------------------------------------------
# Phase 2: New hire state
# ---------------------------------------------------------------
echo "  Checking Phase 2 (new hires)..."

# Check mrivera existence and details
MRIVERA_DATA=$(snipeit_db_query "SELECT u.id, u.email, d.name, l.name, u.activated FROM users u LEFT JOIN departments d ON u.department_id=d.id LEFT JOIN locations l ON u.location_id=l.id WHERE u.username='mrivera' AND u.deleted_at IS NULL LIMIT 1")
MRIVERA_FOUND="false"
MRIVERA_ID=""
MRIVERA_EMAIL=""
MRIVERA_DEPT=""
MRIVERA_LOC=""
if [ -n "$MRIVERA_DATA" ]; then
    MRIVERA_FOUND="true"
    MRIVERA_ID=$(echo "$MRIVERA_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    MRIVERA_EMAIL=$(echo "$MRIVERA_DATA" | awk -F'\t' '{print $2}')
    MRIVERA_DEPT=$(echo "$MRIVERA_DATA" | awk -F'\t' '{print $3}')
    MRIVERA_LOC=$(echo "$MRIVERA_DATA" | awk -F'\t' '{print $4}')
fi

# Check ytanaka existence and details
YTANAKA_DATA=$(snipeit_db_query "SELECT u.id, u.email, d.name, l.name, u.activated FROM users u LEFT JOIN departments d ON u.department_id=d.id LEFT JOIN locations l ON u.location_id=l.id WHERE u.username='ytanaka' AND u.deleted_at IS NULL LIMIT 1")
YTANAKA_FOUND="false"
YTANAKA_ID=""
YTANAKA_EMAIL=""
YTANAKA_DEPT=""
YTANAKA_LOC=""
if [ -n "$YTANAKA_DATA" ]; then
    YTANAKA_FOUND="true"
    YTANAKA_ID=$(echo "$YTANAKA_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    YTANAKA_EMAIL=$(echo "$YTANAKA_DATA" | awk -F'\t' '{print $2}')
    YTANAKA_DEPT=$(echo "$YTANAKA_DATA" | awk -F'\t' '{print $3}')
    YTANAKA_LOC=$(echo "$YTANAKA_DATA" | awk -F'\t' '{print $4}')
fi

# Check if new hires have laptops checked out
MRIVERA_HAS_LAPTOP="false"
if [ -n "$MRIVERA_ID" ]; then
    MRIVERA_LAPTOP_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM assets a JOIN models m ON a.model_id=m.id JOIN categories c ON m.category_id=c.id WHERE a.assigned_to=$MRIVERA_ID AND a.assigned_type LIKE '%User%' AND c.name='Laptops' AND a.deleted_at IS NULL" | tr -d '[:space:]')
    if [ "$MRIVERA_LAPTOP_COUNT" -gt 0 ]; then
        MRIVERA_HAS_LAPTOP="true"
    fi
fi

YTANAKA_HAS_LAPTOP="false"
if [ -n "$YTANAKA_ID" ]; then
    YTANAKA_LAPTOP_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM assets a JOIN models m ON a.model_id=m.id JOIN categories c ON m.category_id=c.id WHERE a.assigned_to=$YTANAKA_ID AND a.assigned_type LIKE '%User%' AND c.name='Laptops' AND a.deleted_at IS NULL" | tr -d '[:space:]')
    if [ "$YTANAKA_LAPTOP_COUNT" -gt 0 ]; then
        YTANAKA_HAS_LAPTOP="true"
    fi
fi

# M365 seats for new hires
MRIVERA_HAS_SEAT="false"
if [ -n "$MRIVERA_ID" ]; then
    MR_SEAT=$(snipeit_db_query "SELECT COUNT(*) FROM license_seats WHERE license_id=$MS365_ID AND assigned_to=$MRIVERA_ID AND deleted_at IS NULL" | tr -d '[:space:]')
    if [ "$MR_SEAT" -gt 0 ]; then
        MRIVERA_HAS_SEAT="true"
    fi
fi

YTANAKA_HAS_SEAT="false"
if [ -n "$YTANAKA_ID" ]; then
    YT_SEAT=$(snipeit_db_query "SELECT COUNT(*) FROM license_seats WHERE license_id=$MS365_ID AND assigned_to=$YTANAKA_ID AND deleted_at IS NULL" | tr -d '[:space:]')
    if [ "$YT_SEAT" -gt 0 ]; then
        YTANAKA_HAS_SEAT="true"
    fi
fi

# ---------------------------------------------------------------
# Phase 3: Warranty audit targets
# ---------------------------------------------------------------
echo "  Checking Phase 3 (warranty audit)..."

L003_JSON=$(build_asset_json "RECON-L003" "$RECON_L003_ID")
L004_JSON=$(build_asset_json "RECON-L004" "$RECON_L004_ID")
L005_JSON=$(build_asset_json "RECON-L005" "$RECON_L005_ID")
L006_JSON=$(build_asset_json "RECON-L006" "$RECON_L006_ID")
D001_JSON=$(build_asset_json "RECON-D001" "$RECON_D001_ID")
MONB_JSON=$(build_asset_json "RECON-MON-B" "$RECON_MONB_ID")

# Check if L003/L004 notes contain the audit text
L003_HAS_NOTE="false"
L003_NOTES=$(snipeit_db_query "SELECT notes FROM assets WHERE id=$RECON_L003_ID AND deleted_at IS NULL" | tr -d '\n')
if echo "$L003_NOTES" | grep -qi "Q1-2026 AUDIT"; then
    L003_HAS_NOTE="true"
fi

L004_HAS_NOTE="false"
L004_NOTES=$(snipeit_db_query "SELECT notes FROM assets WHERE id=$RECON_L004_ID AND deleted_at IS NULL" | tr -d '\n')
if echo "$L004_NOTES" | grep -qi "Q1-2026 AUDIT"; then
    L004_HAS_NOTE="true"
fi

# Check RECON-L002 was NOT flagged by Phase 3 (it was checked in during Phase 1, so not deployed)
L002_NOT_FLAGGED="true"
L002_STATUS=$(snipeit_db_query "SELECT sl.name FROM assets a JOIN status_labels sl ON a.status_id=sl.id WHERE a.id=$RECON_L002_ID AND a.deleted_at IS NULL" | tr -d '\n')
if [ "$L002_STATUS" = "Out for Repair" ]; then
    L002_NOT_FLAGGED="false"
fi

# ---------------------------------------------------------------
# Phase 4: Organizational update
# ---------------------------------------------------------------
echo "  Checking Phase 4 (org update)..."

# Check if Marketing was renamed to Growth & Marketing
DEPT_RENAMED="false"
GROWTH_MARKETING_EXISTS=$(snipeit_db_query "SELECT COUNT(*) FROM departments WHERE name='Growth & Marketing'" | tr -d '[:space:]')
if [ "$GROWTH_MARKETING_EXISTS" -gt 0 ]; then
    DEPT_RENAMED="true"
fi

# Check if Building C - Floor 3 location exists
LOC_CREATED="false"
LOC_ADDRESS=""
BLDGC_DATA=$(snipeit_db_query "SELECT id, address, city, state, zip FROM locations WHERE name='Building C - Floor 3' LIMIT 1")
if [ -n "$BLDGC_DATA" ]; then
    LOC_CREATED="true"
    LOC_ADDRESS=$(echo "$BLDGC_DATA" | awk -F'\t' '{print $2}')
fi

# Check ppatel location
PPATEL_CURRENT_LOC_NAME=$(snipeit_db_query "SELECT l.name FROM users u JOIN locations l ON u.location_id=l.id WHERE u.id=$PPATEL_ID AND u.deleted_at IS NULL" | tr -d '\n')
PPATEL_LOC_UPDATED="false"
if [ "$PPATEL_CURRENT_LOC_NAME" = "Building C - Floor 3" ]; then
    PPATEL_LOC_UPDATED="true"
fi

# ---------------------------------------------------------------
# Build final result JSON
# ---------------------------------------------------------------
echo "  Building result JSON..."

RESULT_JSON=$(cat << JSONEOF
{
  "phase1_departures": {
    "assets": {
      "RECON_L001": $L001_JSON,
      "RECON_MON_A": $MONA_JSON,
      "RECON_L002": $L002_JSON
    },
    "alee_deactivated": $ALEE_DEACTIVATED,
    "bkumar_deactivated": $BKUMAR_DEACTIVATED,
    "alee_m365_seat_removed": $([ "$ALEE_HAS_SEAT" = "false" ] && echo "true" || echo "false"),
    "bkumar_m365_seat_removed": $([ "$BKUMAR_HAS_SEAT" = "false" ] && echo "true" || echo "false")
  },
  "phase2_new_hires": {
    "mrivera": {
      "found": $MRIVERA_FOUND,
      "email": "$(json_escape "$MRIVERA_EMAIL")",
      "department": "$(json_escape "$MRIVERA_DEPT")",
      "location": "$(json_escape "$MRIVERA_LOC")",
      "has_laptop": $MRIVERA_HAS_LAPTOP,
      "has_m365_seat": $MRIVERA_HAS_SEAT
    },
    "ytanaka": {
      "found": $YTANAKA_FOUND,
      "email": "$(json_escape "$YTANAKA_EMAIL")",
      "department": "$(json_escape "$YTANAKA_DEPT")",
      "location": "$(json_escape "$YTANAKA_LOC")",
      "has_laptop": $YTANAKA_HAS_LAPTOP,
      "has_m365_seat": $YTANAKA_HAS_SEAT
    }
  },
  "phase3_warranty_audit": {
    "RECON_L003": $L003_JSON,
    "RECON_L003_has_audit_note": $L003_HAS_NOTE,
    "RECON_L004": $L004_JSON,
    "RECON_L004_has_audit_note": $L004_HAS_NOTE,
    "RECON_L005": $L005_JSON,
    "RECON_L006": $L006_JSON,
    "RECON_D001": $D001_JSON,
    "RECON_MON_B": $MONB_JSON,
    "RECON_L002_not_flagged": $L002_NOT_FLAGGED
  },
  "phase4_org_update": {
    "department_renamed": $DEPT_RENAMED,
    "location_created": $LOC_CREATED,
    "location_address": "$(json_escape "$LOC_ADDRESS")",
    "ppatel_location_updated": $PPATEL_LOC_UPDATED,
    "ppatel_current_location": "$(json_escape "$PPATEL_CURRENT_LOC_NAME")"
  }
}
JSONEOF
)

safe_write_result "/tmp/end_of_quarter_it_reconciliation_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/end_of_quarter_it_reconciliation_result.json"
echo "$RESULT_JSON"
echo "=== end_of_quarter_it_reconciliation export complete ==="
