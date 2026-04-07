#!/bin/bash
set -e
echo "=== Exporting create_attribute_set result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CLIENT_ID=$(get_gardenworld_client_id)

echo "Checking database for Attribute Set 'SER_LOT_TRACK'..."

# Query columns: Value, Name, Description, IsSerNo, IsLot, GuaranteeDays, IsInstanceAttribute, Created(epoch)
# Using separate queries for safety against parsing complex SQL output in bash
# Only selecting the most recent one created
DB_ID=$(idempiere_query "SELECT m_attributeset_id FROM m_attributeset WHERE value='SER_LOT_TRACK' AND ad_client_id=$CLIENT_ID ORDER BY created DESC LIMIT 1" 2>/dev/null || echo "")

RECORD_FOUND="false"
NAME=""
DESC=""
IS_SER_NO="N"
IS_LOT="N"
GUARANTEE_DAYS="0"
IS_INSTANCE="N"
CREATED_EPOCH="0"

if [ -n "$DB_ID" ] && [ "$DB_ID" != "" ]; then
    RECORD_FOUND="true"
    
    # Extract details
    NAME=$(idempiere_query "SELECT name FROM m_attributeset WHERE m_attributeset_id=$DB_ID" 2>/dev/null)
    DESC=$(idempiere_query "SELECT description FROM m_attributeset WHERE m_attributeset_id=$DB_ID" 2>/dev/null)
    IS_SER_NO=$(idempiere_query "SELECT isserno FROM m_attributeset WHERE m_attributeset_id=$DB_ID" 2>/dev/null)
    IS_LOT=$(idempiere_query "SELECT islot FROM m_attributeset WHERE m_attributeset_id=$DB_ID" 2>/dev/null)
    GUARANTEE_DAYS=$(idempiere_query "SELECT guaranteedays FROM m_attributeset WHERE m_attributeset_id=$DB_ID" 2>/dev/null)
    IS_INSTANCE=$(idempiere_query "SELECT isinstanceattribute FROM m_attributeset WHERE m_attributeset_id=$DB_ID" 2>/dev/null)
    CREATED_EPOCH=$(idempiere_query "SELECT EXTRACT(EPOCH FROM created)::bigint FROM m_attributeset WHERE m_attributeset_id=$DB_ID" 2>/dev/null)
    
    echo "Found record ID: $DB_ID"
    echo "Name: $NAME"
    echo "Serial: $IS_SER_NO, Lot: $IS_LOT, Guarantee: $GUARANTEE_DAYS"
else
    echo "No record found with Search Key 'SER_LOT_TRACK'"
fi

# Sanitize strings for JSON (simple escape)
NAME_JSON=$(echo "$NAME" | sed 's/"/\\"/g')
DESC_JSON=$(echo "$DESC" | sed 's/"/\\"/g')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "record_found": $RECORD_FOUND,
    "search_key": "SER_LOT_TRACK",
    "name": "$NAME_JSON",
    "description": "$DESC_JSON",
    "is_ser_no": "$IS_SER_NO",
    "is_lot": "$IS_LOT",
    "guarantee_days": ${GUARANTEE_DAYS:-0},
    "is_instance_attribute": "$IS_INSTANCE",
    "created_epoch": ${CREATED_EPOCH:-0},
    "task_start_epoch": $TASK_START,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="