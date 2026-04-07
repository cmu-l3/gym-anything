#!/bin/bash
echo "=== Exporting manufacturer_data_cleanup results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Read reference IDs
CANON_DELL=$(cat /tmp/mfr_canon_dell.txt 2>/dev/null || echo "0")
CANON_HP=$(cat /tmp/mfr_canon_hp.txt 2>/dev/null || echo "0")
CANON_LENOVO=$(cat /tmp/mfr_canon_lenovo.txt 2>/dev/null || echo "0")

DUP_DELL=$(cat /tmp/mfr_dup_dell.txt 2>/dev/null || echo "0")
DUP_HP=$(cat /tmp/mfr_dup_hp.txt 2>/dev/null || echo "0")
DUP_LENOVO=$(cat /tmp/mfr_dup_lenovo.txt 2>/dev/null || echo "0")

# 1. Check Model Reassignments
get_model_mfr() {
    local model_name="$1"
    local mfr_id=$(snipeit_db_query "SELECT manufacturer_id FROM models WHERE name='$model_name' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
    echo "${mfr_id:-0}"
}

MOD_OPTI_MFR=$(get_model_mfr "OptiPlex 7090")
MOD_LAT_MFR=$(get_model_mfr "Latitude 5520")
MOD_PRO_MFR=$(get_model_mfr "ProBook 450 G8")
MOD_ELI_MFR=$(get_model_mfr "EliteDisplay E243")
MOD_THI_MFR=$(get_model_mfr "ThinkPad X1 Carbon Gen 9")

# 2. Check Duplicate Deletions
check_mfr_deleted() {
    local mfr_id="$1"
    local exists=$(snipeit_db_query "SELECT COUNT(*) FROM manufacturers WHERE id=$mfr_id AND deleted_at IS NULL" | tr -d '[:space:]')
    if [ "$exists" -eq 0 ]; then
        echo "true"
    else
        echo "false"
    fi
}

DUP_DELL_DELETED=$(check_mfr_deleted "$DUP_DELL")
DUP_HP_DELETED=$(check_mfr_deleted "$DUP_HP")
DUP_LENOVO_DELETED=$(check_mfr_deleted "$DUP_LENOVO")

# 3. Check Cisco Systems Manufacturer
CISCO_DATA=$(snipeit_db_query "SELECT id, url, support_url, support_phone, support_email FROM manufacturers WHERE name='Cisco Systems' AND deleted_at IS NULL LIMIT 1")
CISCO_FOUND="false"
CISCO_ID="0"
CISCO_URL=""
CISCO_SUPPORT_URL=""
CISCO_PHONE=""
CISCO_EMAIL=""

if [ -n "$CISCO_DATA" ]; then
    CISCO_FOUND="true"
    CISCO_ID=$(echo "$CISCO_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    CISCO_URL=$(echo "$CISCO_DATA" | awk -F'\t' '{print $2}')
    CISCO_SUPPORT_URL=$(echo "$CISCO_DATA" | awk -F'\t' '{print $3}')
    CISCO_PHONE=$(echo "$CISCO_DATA" | awk -F'\t' '{print $4}')
    CISCO_EMAIL=$(echo "$CISCO_DATA" | awk -F'\t' '{print $5}')
fi

# 4. Check Catalyst 9300 Model
CATALYST_DATA=$(snipeit_db_query "SELECT manufacturer_id, category_id FROM models WHERE name='Catalyst 9300' AND deleted_at IS NULL LIMIT 1")
CATALYST_FOUND="false"
CATALYST_MFR_ID="0"
CATALYST_CAT_NAME=""

if [ -n "$CATALYST_DATA" ]; then
    CATALYST_FOUND="true"
    CATALYST_MFR_ID=$(echo "$CATALYST_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    CATALYST_CAT_ID=$(echo "$CATALYST_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
    if [ -n "$CATALYST_CAT_ID" ]; then
        CATALYST_CAT_NAME=$(snipeit_db_query "SELECT name FROM categories WHERE id=$CATALYST_CAT_ID AND deleted_at IS NULL LIMIT 1" | tr -d '\n')
    fi
fi

# 5. Check Assets Intact
ASSETS_INTACT_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE asset_tag IN ('MFR-CLN-001','MFR-CLN-002','MFR-CLN-003','MFR-CLN-004','MFR-CLN-005') AND deleted_at IS NULL" | tr -d '[:space:]')
if [ "$ASSETS_INTACT_COUNT" -eq 5 ]; then
    ASSETS_INTACT="true"
else
    ASSETS_INTACT="false"
fi

# Build JSON Output
RESULT_JSON=$(cat << JSONEOF
{
  "reference_ids": {
    "canon_dell": $CANON_DELL,
    "canon_hp": $CANON_HP,
    "canon_lenovo": $CANON_LENOVO,
    "dup_dell": $DUP_DELL,
    "dup_hp": $DUP_HP,
    "dup_lenovo": $DUP_LENOVO
  },
  "models_mfr_ids": {
    "optiplex_7090": $MOD_OPTI_MFR,
    "latitude_5520": $MOD_LAT_MFR,
    "probook_450": $MOD_PRO_MFR,
    "elitedisplay_e243": $MOD_ELI_MFR,
    "thinkpad_x1": $MOD_THI_MFR
  },
  "deletions": {
    "dup_dell_deleted": $DUP_DELL_DELETED,
    "dup_hp_deleted": $DUP_HP_DELETED,
    "dup_lenovo_deleted": $DUP_LENOVO_DELETED
  },
  "cisco_systems": {
    "found": $CISCO_FOUND,
    "id": $CISCO_ID,
    "url": "$(json_escape "$CISCO_URL")",
    "support_url": "$(json_escape "$CISCO_SUPPORT_URL")",
    "support_phone": "$(json_escape "$CISCO_PHONE")",
    "support_email": "$(json_escape "$CISCO_EMAIL")"
  },
  "catalyst_9300": {
    "found": $CATALYST_FOUND,
    "mfr_id": $CATALYST_MFR_ID,
    "category_name": "$(json_escape "$CATALYST_CAT_NAME")"
  },
  "assets_intact": $ASSETS_INTACT,
  "assets_intact_count": $ASSETS_INTACT_COUNT
}
JSONEOF
)

safe_write_result "/tmp/manufacturer_cleanup_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/manufacturer_cleanup_result.json"
cat /tmp/manufacturer_cleanup_result.json
echo "=== Export complete ==="