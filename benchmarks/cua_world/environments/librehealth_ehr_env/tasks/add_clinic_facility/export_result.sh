#!/bin/bash
set -e
echo "=== Exporting task results: add_clinic_facility ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check if facility count increased (Anti-gaming)
INITIAL_COUNT=$(cat /tmp/initial_facility_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(librehealth_query "SELECT COUNT(*) FROM facility" 2>/dev/null || echo "0")
COUNT_INCREASED="false"
if [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
    COUNT_INCREASED="true"
fi

# 2. Query the specific facility details
# We use mysql directly via docker exec to get a tab-separated output for easier parsing
# Warning: The query must handle potential NULLs safely
QUERY="SELECT 
    phone, fax, street, city, state, postal_code, 
    federal_ein, facility_npi, facility_taxonomy, 
    pos_code, billing_location, service_location, 
    accepts_assignment, color 
FROM facility 
WHERE name LIKE '%Lakewood Family Health%' 
LIMIT 1"

# Run query and capture output
# We use 'docker exec' pattern directly here to ensure we get raw output we can parse into JSON
FACILITY_DATA=$(docker exec librehealth-db mysql -u libreehr -ps3cret libreehr -N -e "$QUERY" 2>/dev/null || echo "")

FACILITY_FOUND="false"
FACILITY_DETAILS="{}"

if [ -n "$FACILITY_DATA" ]; then
    FACILITY_FOUND="true"
    
    # Parse tab-separated values into JSON using jq or python
    # Data order matches SELECT above:
    # 1:phone, 2:fax, 3:street, 4:city, 5:state, 6:zip, 
    # 7:ein, 8:npi, 9:taxonomy, 10:pos, 11:billing, 12:service, 
    # 13:accepts, 14:color
    
    FACILITY_DETAILS=$(echo "$FACILITY_DATA" | python3 -c '
import sys, json
try:
    line = sys.stdin.read().strip()
    if not line:
        print("{}")
        sys.exit(0)
    parts = line.split("\t")
    # Ensure we have enough parts (pad with empty if needed)
    parts += [""] * (14 - len(parts))
    
    data = {
        "phone": parts[0],
        "fax": parts[1],
        "street": parts[2],
        "city": parts[3],
        "state": parts[4],
        "zip": parts[5],
        "ein": parts[6],
        "npi": parts[7],
        "taxonomy": parts[8],
        "pos_code": parts[9],
        "billing_location": parts[10],
        "service_location": parts[11],
        "accepts_assignment": parts[12],
        "color": parts[13]
    }
    print(json.dumps(data))
except Exception as e:
    print(json.dumps({"error": str(e)}))
')
fi

# 3. Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "count_increased": $COUNT_INCREASED,
    "facility_found": $FACILITY_FOUND,
    "facility_details": $FACILITY_DETAILS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="