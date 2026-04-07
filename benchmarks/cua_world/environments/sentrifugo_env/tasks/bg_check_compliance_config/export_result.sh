#!/bin/bash
echo "=== Exporting bg_check_compliance_config result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png ga

# Helper function to dump a MySQL table to JSON securely
fetch_table_json() {
    local table=$1
    docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -e "SELECT * FROM ${table};" --xml 2>/dev/null | python3 -c '
import xml.etree.ElementTree as ET, sys, json
try:
    tree = ET.parse(sys.stdin)
    rows = []
    for row in tree.findall(".//row"):
        d = {}
        for field in row.findall("field"):
            name = field.attrib.get("name", "")
            if name:
                d[name.lower()] = field.text
        rows.append(d)
    print(json.dumps(rows))
except Exception:
    print("[]")
'
}

# Fetch contents of screening types and agencies tables
TYPES_JSON=$(fetch_table_json "main_bgscreeningtype")
AGENCIES_JSON=$(fetch_table_json "main_bgagencylist")

# Read initial counts
INITIAL_TYPES=$(cat /tmp/initial_types_count 2>/dev/null || echo "0")
INITIAL_AGENCIES=$(cat /tmp/initial_agencies_count 2>/dev/null || echo "0")

# Build the final result JSON
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "initial_types_count": $INITIAL_TYPES,
    "initial_agencies_count": $INITIAL_AGENCIES,
    "types": $TYPES_JSON,
    "agencies": $AGENCIES_JSON,
    "export_timestamp": $(date +%s)
}
EOF

# Move securely
rm -f /tmp/bg_check_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/bg_check_result.json
chmod 666 /tmp/bg_check_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/bg_check_result.json"
echo "=== Export complete ==="