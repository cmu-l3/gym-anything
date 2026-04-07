#!/bin/bash
echo "=== Exporting drone_fleet_maintenance_compliance results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Supplier
SUPPLIER_DATA=$(snipeit_db_query "SELECT id, email FROM suppliers WHERE name='Federal Aviation Administration' AND deleted_at IS NULL LIMIT 1")
if [ -n "$SUPPLIER_DATA" ]; then
    SID=$(echo "$SUPPLIER_DATA" | awk -F'\t' '{print $1}' | tr -d '\r')
    SEM=$(echo "$SUPPLIER_DATA" | awk -F'\t' '{print $2}' | tr -d '\r')
    SUPPLIER_JSON="{\"id\":\"$SID\", \"email\":\"$(json_escape "$SEM")\"}"
else
    SUPPLIER_JSON="null"
fi

# 2. Custom Field
CF_DATA=$(snipeit_db_query "SELECT id, format, db_column FROM custom_fields WHERE name='Total Flight Hours' LIMIT 1")
if [ -n "$CF_DATA" ]; then
    CF_ID=$(echo "$CF_DATA" | awk -F'\t' '{print $1}' | tr -d '\r')
    CF_FMT=$(echo "$CF_DATA" | awk -F'\t' '{print $2}' | tr -d '\r')
    DB_COL=$(echo "$CF_DATA" | awk -F'\t' '{print $3}' | tr -d '\r')
    CF_JSON="{\"id\":\"$CF_ID\", \"format\":\"$(json_escape "$CF_FMT")\", \"db_column\":\"$(json_escape "$DB_COL")\"}"
else
    CF_JSON="null"
fi

# 3. Fieldset Association
ASSOC_EXISTS="false"
if [ -n "$CF_ID" ]; then
    FIELDSET_ID=$(snipeit_db_query "SELECT id FROM custom_fieldsets WHERE name='UAV Metadata' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$FIELDSET_ID" ]; then
        COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM custom_field_custom_fieldset WHERE custom_fieldset_id=$FIELDSET_ID AND custom_field_id=$CF_ID" | tr -d '[:space:]')
        if [ "$COUNT" -gt 0 ]; then ASSOC_EXISTS="true"; fi
    fi
fi

# 4. Assets status and flight hours
ASSETS_JSON="{"
for i in 1 2 3 4; do
    TAG="DRONE-00$i"
    STATUS_NAME=$(snipeit_db_query "SELECT sl.name FROM assets a JOIN status_labels sl ON a.status_id = sl.id WHERE a.asset_tag='$TAG' AND a.deleted_at IS NULL LIMIT 1" | tr -d '\n' | tr -d '\r')
    
    FLIGHT_HOURS="null"
    if [ -n "$DB_COL" ]; then
        # Ensure column was actually created in DB to avoid SQL errors
        COL_EXISTS=$(snipeit_db_query "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_NAME='assets' AND COLUMN_NAME='$DB_COL'" | tr -d '[:space:]')
        if [ "$COL_EXISTS" -gt 0 ]; then
            VAL=$(snipeit_db_query "SELECT $DB_COL FROM assets WHERE asset_tag='$TAG' AND deleted_at IS NULL LIMIT 1" | tr -d '\n' | tr -d '\r')
            if [ -n "$VAL" ] && [ "$VAL" != "NULL" ]; then
                FLIGHT_HOURS="\"$(json_escape "$VAL")\""
            fi
        fi
    fi
    
    ASSETS_JSON+="\"$TAG\": {\"status\": \"$(json_escape "$STATUS_NAME")\", \"flight_hours\": $FLIGHT_HOURS}"
    if [ "$i" -lt 4 ]; then ASSETS_JSON+=", "; fi
done
ASSETS_JSON+="}"

# 5. Maintenances
MAINTENANCES_JSON="["
snipeit_db_query "SELECT a.asset_tag, COALESCE(s.name, ''), m.asset_maintenance_type, m.title, m.start_date, COALESCE(m.completion_date, 'NULL'), m.cost, COALESCE(m.notes, '') FROM asset_maintenances m JOIN assets a ON m.asset_id = a.id LEFT JOIN suppliers s ON m.supplier_id = s.id WHERE a.asset_tag LIKE 'DRONE-%'" > /tmp/maint.tsv

first=true
while IFS=$'\t' read -r tag sup type title start comp cost notes; do
    tag=$(echo "$tag" | tr -d '\r')
    if [ -z "$tag" ]; then continue; fi
    if [ "$first" = true ]; then first=false; else MAINTENANCES_JSON+=","; fi
    
    sup=$(echo "$sup" | tr -d '\r')
    type=$(echo "$type" | tr -d '\r')
    title=$(echo "$title" | tr -d '\r')
    start=$(echo "$start" | tr -d '\r')
    comp=$(echo "$comp" | tr -d '\r')
    cost=$(echo "$cost" | tr -d '\r')
    notes=$(echo "$notes" | tr -d '\r')

    MAINTENANCES_JSON+="{\"asset_tag\":\"$tag\", \"supplier\":\"$(json_escape "$sup")\", \"type\":\"$(json_escape "$type")\", \"title\":\"$(json_escape "$title")\", \"start_date\":\"$start\", \"completion_date\":\"$comp\", \"cost\":\"$cost\", \"notes\":\"$(json_escape "$notes")\"}"
done < /tmp/maint.tsv
MAINTENANCES_JSON+="]"

# Compile final result
RESULT_JSON=$(cat << JSONEOF
{
  "supplier": $SUPPLIER_JSON,
  "custom_field": $CF_JSON,
  "fieldset_association_exists": $ASSOC_EXISTS,
  "assets": $ASSETS_JSON,
  "maintenances": $MAINTENANCES_JSON
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "=== Export complete ==="