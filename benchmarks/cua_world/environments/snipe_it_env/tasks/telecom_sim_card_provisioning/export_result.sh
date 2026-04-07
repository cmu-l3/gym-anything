#!/bin/bash
echo "=== Exporting telecom_sim_card_provisioning results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/telecom_final.png

# Custom Fields
CF_PHONE_EXISTS=$(snipeit_db_query "SELECT COUNT(*) FROM custom_fields WHERE name='Phone Number'" | tr -d '[:space:]')
CF_CARRIER_EXISTS=$(snipeit_db_query "SELECT COUNT(*) FROM custom_fields WHERE name='Carrier'" | tr -d '[:space:]')

CF_PHONE_DB_COLUMN=$(snipeit_db_query "SELECT db_column FROM custom_fields WHERE name='Phone Number' LIMIT 1" | tr -d '[:space:]' | tr -d '\n')
CF_CARRIER_DB_COLUMN=$(snipeit_db_query "SELECT db_column FROM custom_fields WHERE name='Carrier' LIMIT 1" | tr -d '[:space:]' | tr -d '\n')

# Fieldset
FS_ID=$(snipeit_db_query "SELECT id FROM custom_fieldsets WHERE name='Telecom Data' LIMIT 1" | tr -d '[:space:]')
FS_EXISTS="false"
FS_HAS_PHONE="false"
FS_HAS_CARRIER="false"

if [ -n "$FS_ID" ]; then
    FS_EXISTS="true"
    if [ "$CF_PHONE_EXISTS" -gt 0 ]; then
        PHONE_ID=$(snipeit_db_query "SELECT id FROM custom_fields WHERE name='Phone Number' LIMIT 1" | tr -d '[:space:]')
        HAS_PHONE=$(snipeit_db_query "SELECT COUNT(*) FROM custom_field_custom_fieldset WHERE custom_field_id=$PHONE_ID AND custom_fieldset_id=$FS_ID" | tr -d '[:space:]')
        if [ "$HAS_PHONE" -gt 0 ]; then FS_HAS_PHONE="true"; fi
    fi
    if [ "$CF_CARRIER_EXISTS" -gt 0 ]; then
        CARRIER_ID=$(snipeit_db_query "SELECT id FROM custom_fields WHERE name='Carrier' LIMIT 1" | tr -d '[:space:]')
        HAS_CARRIER=$(snipeit_db_query "SELECT COUNT(*) FROM custom_field_custom_fieldset WHERE custom_field_id=$CARRIER_ID AND custom_fieldset_id=$FS_ID" | tr -d '[:space:]')
        if [ "$HAS_CARRIER" -gt 0 ]; then FS_HAS_CARRIER="true"; fi
    fi
fi

# Category
CAT_ID=$(snipeit_db_query "SELECT id FROM categories WHERE name='SIM Cards' AND category_type='asset' LIMIT 1" | tr -d '[:space:]')
CAT_EXISTS="false"
CAT_BOUND_TO_FS="false"
if [ -n "$CAT_ID" ]; then
    CAT_EXISTS="true"
    CAT_FS=$(snipeit_db_query "SELECT fieldset_id FROM categories WHERE id=$CAT_ID" | tr -d '[:space:]')
    if [ "$CAT_FS" = "$FS_ID" ] && [ -n "$FS_ID" ]; then
        CAT_BOUND_TO_FS="true"
    fi
fi

# Manufacturer
MAN_EXISTS=$(snipeit_db_query "SELECT COUNT(*) FROM manufacturers WHERE name='Telecom Providers'" | tr -d '[:space:]')

# Model
MOD_ID=$(snipeit_db_query "SELECT id FROM models WHERE name='5G Business SIM' LIMIT 1" | tr -d '[:space:]')
MOD_EXISTS="false"
MOD_CORRECT_CAT="false"
if [ -n "$MOD_ID" ]; then
    MOD_EXISTS="true"
    MOD_CAT=$(snipeit_db_query "SELECT category_id FROM models WHERE id=$MOD_ID" | tr -d '[:space:]')
    if [ "$MOD_CAT" = "$CAT_ID" ] && [ -n "$CAT_ID" ]; then
        MOD_CORRECT_CAT="true"
    fi
fi

# Function to get individual SIM card data securely
get_sim_data() {
    local tag="$1"
    local data=$(snipeit_db_query "SELECT id, serial, model_id, assigned_to, assigned_type FROM assets WHERE asset_tag='$tag' AND deleted_at IS NULL LIMIT 1")
    if [ -z "$data" ]; then
        echo "{\"tag\": \"$tag\", \"found\": false}"
        return
    fi
    
    local id=$(echo "$data" | awk -F'\t' '{print $1}')
    local serial=$(echo "$data" | awk -F'\t' '{print $2}')
    local model_id=$(echo "$data" | awk -F'\t' '{print $3}')
    local assigned_to=$(echo "$data" | awk -F'\t' '{print $4}' | tr -d '[:space:]')
    local assigned_type=$(echo "$data" | awk -F'\t' '{print $5}' | tr -d '[:space:]')
    
    local phone=""
    local carrier=""
    
    # Securely retrieve dynamic custom fields if columns exist
    if [ -n "$CF_PHONE_DB_COLUMN" ]; then
        local col_exists=$(snipeit_db_query "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='snipeit' AND TABLE_NAME='assets' AND COLUMN_NAME='$CF_PHONE_DB_COLUMN'" | tr -d '[:space:]')
        if [ "$col_exists" -gt 0 ]; then
            phone=$(snipeit_db_query "SELECT $CF_PHONE_DB_COLUMN FROM assets WHERE id=$id" | tr -d '\n')
        fi
    fi
    
    if [ -n "$CF_CARRIER_DB_COLUMN" ]; then
        local col_exists=$(snipeit_db_query "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='snipeit' AND TABLE_NAME='assets' AND COLUMN_NAME='$CF_CARRIER_DB_COLUMN'" | tr -d '[:space:]')
        if [ "$col_exists" -gt 0 ]; then
            carrier=$(snipeit_db_query "SELECT $CF_CARRIER_DB_COLUMN FROM assets WHERE id=$id" | tr -d '\n')
        fi
    fi
    
    echo "{\"tag\": \"$tag\", \"found\": true, \"id\": $id, \"serial\": \"$(json_escape "$serial")\", \"model_id\": $model_id, \"assigned_to\": \"$assigned_to\", \"assigned_type\": \"$(json_escape "$assigned_type")\", \"phone\": \"$(json_escape "$phone")\", \"carrier\": \"$(json_escape "$carrier")\"}"
}

SIM1_JSON=$(get_sim_data "SIM-001")
SIM2_JSON=$(get_sim_data "SIM-002")
SIM3_JSON=$(get_sim_data "SIM-003")

# Get target phone asset IDs
MOB1_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='MOB-001' AND deleted_at IS NULL" | tr -d '[:space:]')
MOB2_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='MOB-002' AND deleted_at IS NULL" | tr -d '[:space:]')
MOB3_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='MOB-003' AND deleted_at IS NULL" | tr -d '[:space:]')

# Build final result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "custom_fields": {
    "phone_exists": $( [ "$CF_PHONE_EXISTS" -gt 0 ] && echo "true" || echo "false" ),
    "carrier_exists": $( [ "$CF_CARRIER_EXISTS" -gt 0 ] && echo "true" || echo "false" )
  },
  "fieldset": {
    "exists": $FS_EXISTS,
    "has_phone": $FS_HAS_PHONE,
    "has_carrier": $FS_HAS_CARRIER
  },
  "category": {
    "exists": $CAT_EXISTS,
    "bound_to_fs": $CAT_BOUND_TO_FS
  },
  "manufacturer": {
    "exists": $( [ "$MAN_EXISTS" -gt 0 ] && echo "true" || echo "false" )
  },
  "model": {
    "exists": $MOD_EXISTS,
    "correct_category": $MOD_CORRECT_CAT
  },
  "sims": {
    "SIM-001": $SIM1_JSON,
    "SIM-002": $SIM2_JSON,
    "SIM-003": $SIM3_JSON
  },
  "mobs": {
    "MOB-001": "${MOB1_ID}",
    "MOB-002": "${MOB2_ID}",
    "MOB-003": "${MOB3_ID}"
  }
}
JSONEOF
)

safe_write_result "/tmp/telecom_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/telecom_result.json"
echo "$RESULT_JSON"
echo "=== telecom_sim_card_provisioning export complete ==="