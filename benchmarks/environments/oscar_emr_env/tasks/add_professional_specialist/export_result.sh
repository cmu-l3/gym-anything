#!/bin/bash
echo "=== Exporting add_professional_specialist result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the specialist record
# We select all relevant fields to verify content accuracy
# Using LOWER() for case-insensitive matching on name to find the record ID first
echo "Querying database for Rajesh Patel..."

# Get the ID of the newly created record (if any)
# We look for a record created/modified recently or simply matching the name
# Since we deleted it in setup, any matching record is likely from the agent
SPECIALIST_ID=$(oscar_query "SELECT id FROM professionalSpecialists WHERE firstName='Rajesh' AND lastName='Patel' ORDER BY id DESC LIMIT 1")

# If not found exact, try case insensitive
if [ -z "$SPECIALIST_ID" ]; then
    SPECIALIST_ID=$(oscar_query "SELECT id FROM professionalSpecialists WHERE LOWER(firstName)='rajesh' AND LOWER(lastName)='patel' ORDER BY id DESC LIMIT 1")
fi

RECORD_FOUND="false"
SPEC_DATA="{}"
FINAL_COUNT=$(oscar_query "SELECT COUNT(*) FROM professionalSpecialists" 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_count.txt 2>/dev/null || echo "0")

if [ -n "$SPECIALIST_ID" ]; then
    RECORD_FOUND="true"
    # Fetch details using the ID
    # Note: Using python to safely construct JSON to avoid bash string escaping hell
    SPEC_DATA=$(docker exec oscar-db mysql -u oscar -poscar oscar -N -e \
        "SELECT firstName, lastName, specType, streetAddress, phone, fax, email, website, annotation \
         FROM professionalSpecialists WHERE id=$SPECIALIST_ID" | \
        python3 -c '
import sys, json
try:
    # Read tab-separated line from stdin
    line = sys.stdin.read().strip()
    if line:
        parts = line.split("\t")
        # Handle potential missing columns by checking length, fill with empty string
        parts += [""] * (9 - len(parts))
        data = {
            "firstName": parts[0],
            "lastName": parts[1],
            "specType": parts[2],
            "streetAddress": parts[3],
            "phone": parts[4],
            "fax": parts[5],
            "email": parts[6],
            "website": parts[7],
            "annotation": parts[8]
        }
        print(json.dumps(data))
    else:
        print("{}")
except Exception as e:
    print(json.dumps({"error": str(e)}))
')
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "final_count": $FINAL_COUNT,
    "record_found": $RECORD_FOUND,
    "record_id": "${SPECIALIST_ID:-0}",
    "record_data": $SPEC_DATA
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