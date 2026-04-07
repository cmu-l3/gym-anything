#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Create Textile Unit Flow Result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ============================================================
# 1. Close OpenLCA to release database lock
# ============================================================
echo "Closing OpenLCA for verification..."
close_openlca
sleep 5

# ============================================================
# 2. Identify Active Database
# ============================================================
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
# Find the database that was most recently modified
ACTIVE_DB=$(ls -td "$DB_DIR"/*/ 2>/dev/null | head -1)

if [ -z "$ACTIVE_DB" ]; then
    echo "No database found!"
    # Export empty failure result
    cat > /tmp/task_result.json << EOF
{
    "db_found": false,
    "error": "No database found in workspace"
}
EOF
    exit 0
fi

echo "Verifying against database: $ACTIVE_DB"

# ============================================================
# 3. Query Database for Created Objects
# ============================================================

# SQL Queries to check for our specific objects
# We use case-insensitive matching for names to be lenient

# A. Check Unit Group "Units of linear density"
UG_QUERY="SELECT ID, NAME FROM TBL_UNIT_GROUPS WHERE LOWER(NAME) LIKE '%linear density%';"
UG_RESULT=$(derby_query "$ACTIVE_DB" "$UG_QUERY")
UG_ID=$(echo "$UG_RESULT" | grep -oP '^\s*\K\d+(?=\s*\|)' | head -1 || echo "")
UG_NAME=$(echo "$UG_RESULT" | grep "$UG_ID" | cut -d'|' -f2 | xargs || echo "")

echo "Unit Group ID: $UG_ID ($UG_NAME)"

# B. Check Units if Group Found
UNITS_JSON="[]"
if [ -n "$UG_ID" ]; then
    # Get all units for this group
    UNIT_QUERY="SELECT NAME, CONVERSION_FACTOR, IS_REFERENCE FROM TBL_UNITS WHERE F_UNIT_GROUP = $UG_ID;"
    UNIT_RESULT=$(derby_query "$ACTIVE_DB" "$UNIT_QUERY")
    
    # Parse Derby output into JSON array
    # Derby output format is typically: ID | NAME | ...
    # We'll use python to parse this text output more reliably
    
    UNITS_JSON=$(python3 -c "
import sys, re, json
output = '''$UNIT_RESULT'''
units = []
for line in output.splitlines():
    if '|' in line and not line.strip().startswith('NAME'):
        parts = [p.strip() for p in line.split('|')]
        if len(parts) >= 3:
            units.append({
                'name': parts[0],
                'factor': float(parts[1]),
                'is_ref': parts[2]
            })
print(json.dumps(units))
")
fi

# C. Check Flow Property "Linear density"
# Must reference the Unit Group we found
FP_ID=""
FP_NAME=""
FP_LINKED_CORRECTLY="false"

if [ -n "$UG_ID" ]; then
    FP_QUERY="SELECT ID, NAME, F_UNIT_GROUP FROM TBL_FLOW_PROPERTIES WHERE LOWER(NAME) LIKE '%linear density%' AND F_UNIT_GROUP = $UG_ID;"
    FP_RESULT=$(derby_query "$ACTIVE_DB" "$FP_QUERY")
    FP_ID=$(echo "$FP_RESULT" | grep -oP '^\s*\K\d+(?=\s*\|)' | head -1 || echo "")
    
    if [ -n "$FP_ID" ]; then
        FP_NAME=$(echo "$FP_RESULT" | grep "$FP_ID" | cut -d'|' -f2 | xargs)
        FP_LINKED_CORRECTLY="true"
    fi
fi

echo "Flow Property ID: $FP_ID ($FP_NAME)"

# D. Check Product Flow "Polyester staple fiber"
# Must reference the Flow Property we found
FLOW_ID=""
FLOW_NAME=""
FLOW_LINKED_CORRECTLY="false"
FLOW_IS_PRODUCT="false"

if [ -n "$FP_ID" ]; then
    # Check for flow with name 'polyester' and referencing our FP
    # FLOW_TYPE: 0=Elementary, 1=Product, 2=Waste
    FLOW_QUERY="SELECT ID, NAME, FLOW_TYPE, F_REFERENCE_FLOW_PROPERTY FROM TBL_FLOWS WHERE LOWER(NAME) LIKE '%polyester%' AND F_REFERENCE_FLOW_PROPERTY = $FP_ID;"
    FLOW_RESULT=$(derby_query "$ACTIVE_DB" "$FLOW_QUERY")
    FLOW_ID=$(echo "$FLOW_RESULT" | grep -oP '^\s*\K\d+(?=\s*\|)' | head -1 || echo "")
    
    if [ -n "$FLOW_ID" ]; then
        FLOW_NAME=$(echo "$FLOW_RESULT" | grep "$FLOW_ID" | cut -d'|' -f2 | xargs)
        FLOW_TYPE=$(echo "$FLOW_RESULT" | grep "$FLOW_ID" | cut -d'|' -f3 | xargs)
        FLOW_LINKED_CORRECTLY="true"
        if [ "$FLOW_TYPE" = "1" ]; then
            FLOW_IS_PRODUCT="true"
        fi
    fi
fi

echo "Flow ID: $FLOW_ID ($FLOW_NAME)"

# ============================================================
# 4. Construct JSON Result
# ============================================================

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "db_found": true,
    "active_db": "$ACTIVE_DB",
    "unit_group": {
        "found": $([ -n "$UG_ID" ] && echo "true" || echo "false"),
        "id": "${UG_ID:-0}",
        "name": "$UG_NAME",
        "units": $UNITS_JSON
    },
    "flow_property": {
        "found": $([ -n "$FP_ID" ] && echo "true" || echo "false"),
        "id": "${FP_ID:-0}",
        "name": "$FP_NAME",
        "linked_to_ug": $FP_LINKED_CORRECTLY
    },
    "flow": {
        "found": $([ -n "$FLOW_ID" ] && echo "true" || echo "false"),
        "id": "${FLOW_ID:-0}",
        "name": "$FLOW_NAME",
        "linked_to_fp": $FLOW_LINKED_CORRECTLY,
        "is_product": $FLOW_IS_PRODUCT
    },
    "timestamp": "$(date -Iseconds)",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with safe permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="