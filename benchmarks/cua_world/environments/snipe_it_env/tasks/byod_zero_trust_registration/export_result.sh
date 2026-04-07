#!/bin/bash
echo "=== Exporting byod_zero_trust_registration results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Read baselines
INITIAL_ASSET_COUNT=$(cat /tmp/initial_asset_count.txt 2>/dev/null || echo "0")
MAX_ASSET_ID_START=$(cat /tmp/max_asset_id_start.txt 2>/dev/null || echo "0")
CURRENT_ASSET_COUNT=$(get_asset_count)

# --- 1. Query Custom Fields ---
MAC_FIELD_ID=$(snipeit_db_query "SELECT id FROM custom_fields WHERE name='Network MAC Address' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
MAC_FIELD_FMT=$(snipeit_db_query "SELECT format FROM custom_fields WHERE name='Network MAC Address' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
OS_FIELD_ID=$(snipeit_db_query "SELECT id FROM custom_fields WHERE name='Mobile OS Version' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
OS_FIELD_FMT=$(snipeit_db_query "SELECT format FROM custom_fields WHERE name='Mobile OS Version' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')

# --- 2. Query Custom Fieldset ---
FIELDSET_ID=$(snipeit_db_query "SELECT id FROM custom_fieldsets WHERE name='BYOD Device Info' LIMIT 1" | tr -d '[:space:]')
MAC_LINKED="false"
OS_LINKED="false"
if [ -n "$FIELDSET_ID" ]; then
    if [ -n "$MAC_FIELD_ID" ] && [ $(snipeit_db_query "SELECT COUNT(*) FROM custom_field_custom_fieldset WHERE custom_fieldset_id=$FIELDSET_ID AND custom_field_id=$MAC_FIELD_ID" | tr -d '[:space:]') -gt 0 ]; then
        MAC_LINKED="true"
    fi
    if [ -n "$OS_FIELD_ID" ] && [ $(snipeit_db_query "SELECT COUNT(*) FROM custom_field_custom_fieldset WHERE custom_fieldset_id=$FIELDSET_ID AND custom_field_id=$OS_FIELD_ID" | tr -d '[:space:]') -gt 0 ]; then
        OS_LINKED="true"
    fi
fi

# --- 3. Query Status Label ---
STATUS_LABEL_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='BYOD - Approved' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
STATUS_DEPLOYABLE=$(snipeit_db_query "SELECT deployable FROM status_labels WHERE id='$STATUS_LABEL_ID' LIMIT 1" | tr -d '[:space:]')

# --- 4. Query Asset Model ---
MODEL_DATA=$(snipeit_db_query "SELECT m.id, m.fieldset_id, m.manufacturer_id, m.category_id, c.name, mfg.name FROM models m LEFT JOIN categories c ON m.category_id=c.id LEFT JOIN manufacturers mfg ON m.manufacturer_id=mfg.id WHERE m.name='Personal Smartphone' AND m.deleted_at IS NULL LIMIT 1")
MODEL_ID=""
MODEL_FIELDSET_ID=""
MODEL_CAT_NAME=""
MODEL_MFG_NAME=""
if [ -n "$MODEL_DATA" ]; then
    MODEL_ID=$(echo "$MODEL_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    MODEL_FIELDSET_ID=$(echo "$MODEL_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
    MODEL_CAT_NAME=$(echo "$MODEL_DATA" | awk -F'\t' '{print $5}' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    MODEL_MFG_NAME=$(echo "$MODEL_DATA" | awk -F'\t' '{print $6}' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
fi

# --- 5. Query Assets via API ---
get_asset_json() {
    local tag=$1
    local token=$(get_api_token)
    local resp=$(curl -s -H "Authorization: Bearer $token" -H "Accept: application/json" "http://localhost:8000/api/v1/hardware/bytag/$tag")
    
    if echo "$resp" | grep -q '"id"'; then
        local id=$(echo "$resp" | jq -r '.id // 0')
        local cost=$(echo "$resp" | jq -r '.purchase_cost // "0.00"')
        local status=$(echo "$resp" | jq -r '.status_label.name // ""')
        local user=$(echo "$resp" | jq -r '.assigned_to.username // ""')
        
        # Try to find custom fields exactly, fallback to substring match
        local mac=$(echo "$resp" | jq -r '.custom_fields["Network MAC Address"].value // ""')
        if [ "$mac" = "" ] || [ "$mac" = "null" ]; then
            mac=$(echo "$resp" | jq -r '.custom_fields | to_entries[]? | select(.key | ascii_downcase | contains("mac")) | .value.value // ""' | head -1)
        fi
        
        local os=$(echo "$resp" | jq -r '.custom_fields["Mobile OS Version"].value // ""')
        if [ "$os" = "" ] || [ "$os" = "null" ]; then
            os=$(echo "$resp" | jq -r '.custom_fields | to_entries[]? | select(.key | ascii_downcase | contains("os")) | .value.value // ""' | head -1)
        fi

        echo "{\"found\":true, \"id\":$id, \"cost\":\"$(json_escape "$cost")\", \"status\":\"$(json_escape "$status")\", \"user\":\"$(json_escape "$user")\", \"mac\":\"$(json_escape "$mac")\", \"os\":\"$(json_escape "$os")\"}"
    else
        echo "{\"found\":false}"
    fi
}

ASSET_1=$(get_asset_json "BYOD-001")
ASSET_2=$(get_asset_json "BYOD-002")
ASSET_3=$(get_asset_json "BYOD-003")

# Build Result JSON
RESULT_JSON=$(cat << EOF
{
  "initial_asset_count": $INITIAL_ASSET_COUNT,
  "max_asset_id_start": $MAX_ASSET_ID_START,
  "current_asset_count": $CURRENT_ASSET_COUNT,
  "custom_fields": {
    "mac_format": "$(json_escape "$MAC_FIELD_FMT")",
    "os_format": "$(json_escape "$OS_FIELD_FMT")"
  },
  "fieldset": {
    "exists": $([ -n "$FIELDSET_ID" ] && echo "true" || echo "false"),
    "mac_linked": $MAC_LINKED,
    "os_linked": $OS_LINKED
  },
  "status_label": {
    "exists": $([ -n "$STATUS_LABEL_ID" ] && echo "true" || echo "false"),
    "deployable": $([ "$STATUS_DEPLOYABLE" = "1" ] && echo "true" || echo "false")
  },
  "model": {
    "exists": $([ -n "$MODEL_ID" ] && echo "true" || echo "false"),
    "fieldset_id": "$(json_escape "$MODEL_FIELDSET_ID")",
    "target_fieldset_id": "$(json_escape "$FIELDSET_ID")",
    "category": "$(json_escape "$MODEL_CAT_NAME")",
    "manufacturer": "$(json_escape "$MODEL_MFG_NAME")"
  },
  "assets": {
    "BYOD-001": $ASSET_1,
    "BYOD-002": $ASSET_2,
    "BYOD-003": $ASSET_3
  }
}
EOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json