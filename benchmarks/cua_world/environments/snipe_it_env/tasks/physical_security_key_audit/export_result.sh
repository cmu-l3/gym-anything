#!/bin/bash
echo "=== Exporting physical_security_key_audit results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot as proof of completion
take_screenshot /tmp/task_final.png

# Read injected IDs
ASSET_004_ID=$(cat /tmp/asset_004_id.txt 2>/dev/null || echo "0")
ASSET_009_ID=$(cat /tmp/asset_009_id.txt 2>/dev/null || echo "0")
ASSET_015_ID=$(cat /tmp/asset_015_id.txt 2>/dev/null || echo "0")
CAT_KEYS_ID=$(cat /tmp/cat_keys_id.txt 2>/dev/null || echo "0")
USER_SHARDING_ID=$(cat /tmp/user_sharding_id.txt 2>/dev/null || echo "0")

# 1. Custom Fields Status
FIELD_CUT_CODE=$(snipeit_db_query "SELECT id FROM custom_fields WHERE name='Key Cut Code' LIMIT 1" | tr -d '[:space:]')
FIELD_ZONE=$(snipeit_db_query "SELECT id FROM custom_fields WHERE name='Access Zone' LIMIT 1" | tr -d '[:space:]')

CUT_CODE_FOUND="false"
ZONE_FOUND="false"
if [ -n "$FIELD_CUT_CODE" ] && [ "$FIELD_CUT_CODE" != "NULL" ]; then CUT_CODE_FOUND="true"; fi
if [ -n "$FIELD_ZONE" ] && [ "$FIELD_ZONE" != "NULL" ]; then ZONE_FOUND="true"; fi

# 2. Custom Fieldset Status & Category Linkage
FIELDSET=$(snipeit_db_query "SELECT id FROM custom_fieldsets WHERE name='Physical Security Keys' LIMIT 1" | tr -d '[:space:]')
FIELDSET_FOUND="false"
FIELDSET_HAS_CUT_CODE="false"
FIELDSET_HAS_ZONE="false"
CATEGORY_LINKED="false"

if [ -n "$FIELDSET" ] && [ "$FIELDSET" != "NULL" ]; then
    FIELDSET_FOUND="true"
    
    # Check if Cut Code is in the fieldset
    if [ "$CUT_CODE_FOUND" = "true" ]; then
        LINK1=$(snipeit_db_query "SELECT custom_field_id FROM custom_field_custom_fieldset WHERE custom_fieldset_id=$FIELDSET AND custom_field_id=$FIELD_CUT_CODE")
        if [ -n "$LINK1" ]; then FIELDSET_HAS_CUT_CODE="true"; fi
    fi
    
    # Check if Access Zone is in the fieldset
    if [ "$ZONE_FOUND" = "true" ]; then
        LINK2=$(snipeit_db_query "SELECT custom_field_id FROM custom_field_custom_fieldset WHERE custom_fieldset_id=$FIELDSET AND custom_field_id=$FIELD_ZONE")
        if [ -n "$LINK2" ]; then FIELDSET_HAS_ZONE="true"; fi
    fi
    
    # Check category linkage
    CAT_FIELDSET=$(snipeit_db_query "SELECT fieldset_id FROM categories WHERE id=$CAT_KEYS_ID" | tr -d '[:space:]')
    if [ "$CAT_FIELDSET" = "$FIELDSET" ]; then
        CATEGORY_LINKED="true"
    fi
fi

# 3. Asset 004 status (Lost/Stolen check)
ASSET_004_STATUS=$(snipeit_db_query "SELECT status_id FROM assets WHERE id=$ASSET_004_ID" | tr -d '[:space:]')
STATUS_NAME=$(snipeit_db_query "SELECT name FROM status_labels WHERE id=$ASSET_004_STATUS" | tr -d '\n')
ASSET_004_LOST="false"
if echo "$STATUS_NAME" | grep -qi "Lost"; then
    ASSET_004_LOST="true"
fi

# 4. Asset 009 assignments (Replacement assigned check)
ASSIGNED_TO=$(snipeit_db_query "SELECT assigned_to FROM assets WHERE id=$ASSET_009_ID" | tr -d '[:space:]')
ASSET_009_ASSIGNED="false"
if [ "$ASSIGNED_TO" = "$USER_SHARDING_ID" ]; then
    ASSET_009_ASSIGNED="true"
fi

# 5. Asset 015 expected checkin date
ASSET_015_EXPECTED_CHECKIN=$(snipeit_db_query "SELECT expected_checkin FROM assets WHERE id=$ASSET_015_ID" | tr -d '\n')

# 6. Fetch API payload to verify dynamically named Custom Fields on Asset 009
snipeit_api GET "hardware/$ASSET_009_ID" "" > /tmp/asset_009_api.json
chmod 666 /tmp/asset_009_api.json 2>/dev/null || true

# Assemble Result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "cut_code_found": $CUT_CODE_FOUND,
  "zone_found": $ZONE_FOUND,
  "fieldset_found": $FIELDSET_FOUND,
  "fieldset_has_cut_code": $FIELDSET_HAS_CUT_CODE,
  "fieldset_has_zone": $FIELDSET_HAS_ZONE,
  "category_linked": $CATEGORY_LINKED,
  "asset_004_lost": $ASSET_004_LOST,
  "asset_004_status_name": "$(json_escape "$STATUS_NAME")",
  "asset_009_assigned_to_sharding": $ASSET_009_ASSIGNED,
  "asset_015_expected_checkin": "$(json_escape "$ASSET_015_EXPECTED_CHECKIN")"
}
JSONEOF
)

safe_write_result "/tmp/physical_security_key_audit_result.json" "$RESULT_JSON"

echo "Result JSON saved."
echo "=== Export complete ==="