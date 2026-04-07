#!/bin/bash
# Export script for Custom Digital Unit Flow task
# Verifies the internal Derby database state for the created ontology objects

source /workspace/scripts/task_utils.sh

echo "=== Exporting Custom Digital Unit Flow Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Capture Task info
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
OPENLCA_RUNNING=$(is_openlca_running && echo "true" || echo "false")

# ============================================================
# DATABASE INSPECTION
# We need to find the active database to query it
# ============================================================

# Close OpenLCA to ensure Derby lock is released (critical for querying)
if [ "$OPENLCA_RUNNING" = "true" ]; then
    echo "Closing OpenLCA to query database..."
    close_openlca
    sleep 3
fi

DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
MAX_MTIME=0

# Find the most recently modified database
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    MTIME=$(stat -c %Y "$db_path" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$MAX_MTIME" ]; then
        MAX_MTIME="$MTIME"
        ACTIVE_DB="$db_path"
    fi
done

echo "Active database for verification: $ACTIVE_DB"

# Initialize result variables
UNIT_GROUP_FOUND="false"
UNITS_JSON="[]"
FLOW_PROPERTY_JSON="{}"
FLOW_JSON="{}"
PROCESS_JSON="{}"
DB_FOUND="false"

if [ -n "$ACTIVE_DB" ]; then
    DB_FOUND="true"

    # 1. Query Unit Group "Digital Units"
    echo "Querying Unit Groups..."
    UG_QUERY="SELECT ID, NAME FROM TBL_UNIT_GROUPS WHERE LOWER(NAME) = 'digital units'"
    UG_RESULT=$(derby_query "$ACTIVE_DB" "$UG_QUERY")
    
    # Extract ID if found
    UG_ID=$(echo "$UG_RESULT" | grep -v "^ij>" | grep -A 1 "ID" | tail -1 | awk '{print $1}' | tr -d ' ' || echo "")
    
    if [ -n "$UG_ID" ] && [ "$UG_ID" != "ID" ] && [ "$UG_ID" != "---" ]; then
        UNIT_GROUP_FOUND="true"
        echo "Found Unit Group ID: $UG_ID"

        # 2. Query Units in this Group
        echo "Querying Units..."
        UNITS_QUERY="SELECT NAME, CONVERSION_FACTOR, REF_UNIT FROM TBL_UNITS WHERE F_UNIT_GROUP = $UG_ID"
        UNITS_RESULT=$(derby_query "$ACTIVE_DB" "$UNITS_QUERY")
        
        # Parse simplified units list for JSON
        # Output format usually: 
        # NAME             |CONVERSION_&|REF_UNIT
        # ---------------------------------------
        # Terabyte         |1.0         |1       
        # Gigabyte         |0.001       |0       
        
        # We'll use python to robustly parse the Derby output and creating the JSON fragment
        UNITS_JSON=$(python3 -c "
import sys, re, json
content = '''$UNITS_RESULT'''
units = []
lines = content.split('\n')
data_started = False
for line in lines:
    if line.strip().startswith('---'):
        data_started = True
        continue
    if data_started and '|' in line:
        parts = [p.strip() for p in line.split('|')]
        if len(parts) >= 3:
            try:
                units.append({'name': parts[0], 'factor': float(parts[1]), 'is_ref': parts[2] == '1'})
            except: pass
    if 'rows selected' in line: break
print(json.dumps(units))
")
        
        # 3. Query Flow Property "Data Amount"
        echo "Querying Flow Property..."
        FP_QUERY="SELECT ID, NAME FROM TBL_FLOW_PROPERTIES WHERE LOWER(NAME) = 'data amount' AND F_UNIT_GROUP = $UG_ID"
        FP_RESULT=$(derby_query "$ACTIVE_DB" "$FP_QUERY")
        FP_ID=$(echo "$FP_RESULT" | grep -v "^ij>" | grep -A 1 "ID" | tail -1 | awk '{print $1}' | tr -d ' ' || echo "")
        
        if [ -n "$FP_ID" ] && [ "$FP_ID" != "ID" ] && [ "$FP_ID" != "---" ]; then
            FLOW_PROPERTY_JSON="{\"found\": true, \"id\": \"$FP_ID\", \"linked_to_unit_group\": true}"
            echo "Found Flow Property ID: $FP_ID"

            # 4. Query Flow "Cloud Data Service"
            echo "Querying Flow..."
            FLOW_QUERY="SELECT ID, NAME FROM TBL_FLOWS WHERE LOWER(NAME) = 'cloud data service' AND F_FLOW_PROPERTY = $FP_ID"
            FLOW_RESULT=$(derby_query "$ACTIVE_DB" "$FLOW_QUERY")
            FLOW_ID=$(echo "$FLOW_RESULT" | grep -v "^ij>" | grep -A 1 "ID" | tail -1 | awk '{print $1}' | tr -d ' ' || echo "")
            
            if [ -n "$FLOW_ID" ] && [ "$FLOW_ID" != "ID" ] && [ "$FLOW_ID" != "---" ]; then
                FLOW_JSON="{\"found\": true, \"id\": \"$FLOW_ID\", \"linked_to_property\": true}"
                echo "Found Flow ID: $FLOW_ID"
                
                # 5. Query Process "Data Center Operation" utilizing this flow
                # We verify if there is an exchange in 'Data Center Operation' with this flow ID and amount 1.0
                echo "Querying Process Exchanges..."
                PROC_QUERY="SELECT p.NAME, e.RESULTING_AMOUNT_VALUE FROM TBL_EXCHANGES e JOIN TBL_PROCESSES p ON e.F_OWNER = p.ID WHERE LOWER(p.NAME) = 'data center operation' AND e.F_FLOW = $FLOW_ID"
                PROC_RESULT=$(derby_query "$ACTIVE_DB" "$PROC_QUERY")
                
                PROCESS_JSON=$(python3 -c "
import sys, re, json
content = '''$PROC_RESULT'''
found = False
amount = 0.0
if 'Data Center Operation' in content:
    lines = content.split('\n')
    for line in lines:
        if '|' in line and 'Data Center Operation' in line:
            parts = line.split('|')
            if len(parts) >= 2:
                try:
                    val = float(parts[1].strip())
                    if val > 0:
                        amount = val
                        found = True
                        break
                except: pass
print(json.dumps({'found': found, 'amount': amount}))
")
            fi
        fi
    fi
else
    echo "No active database found to query."
fi

# ============================================================
# EXPORT JSON RESULT
# ============================================================

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "db_found": $DB_FOUND,
    "unit_group_found": $UNIT_GROUP_FOUND,
    "units": $UNITS_JSON,
    "flow_property": $FLOW_PROPERTY_JSON,
    "flow": $FLOW_JSON,
    "process": $PROCESS_JSON,
    "openlca_was_running": $OPENLCA_RUNNING,
    "screenshot_path": "/tmp/task_end_screenshot.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result export complete:"
cat /tmp/task_result.json