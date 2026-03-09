#!/bin/bash
echo "=== Exporting Create Order Frequency Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

echo "Querying OpenMRS API for task validation..."

# 1. Check if Concept exists
CONCEPT_RESP=$(openmrs_api_get "/concept?q=5+Times+Daily&v=full")
CONCEPT_EXISTS="false"
CONCEPT_UUID=""
CONCEPT_CLASS=""
CONCEPT_DATATYPE=""

# Use Python to robustly parse the JSON response
eval $(echo "$CONCEPT_RESP" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    results = data.get('results', [])
    found = False
    for res in results:
        # Match exact name
        if res.get('name', {}).get('display') == '5 Times Daily':
            print(f'CONCEPT_EXISTS=true')
            print(f'CONCEPT_UUID={res.get(\"uuid\", \"\")}')
            print(f'CONCEPT_CLASS=\"{res.get(\"conceptClass\", {}).get(\"display\", \"\")}\"')
            print(f'CONCEPT_DATATYPE=\"{res.get(\"datatype\", {}).get(\"display\", \"\")}\"')
            found = True
            break
    if not found:
        print('CONCEPT_EXISTS=false')
except Exception as e:
    print('CONCEPT_EXISTS=false')
")

# 2. Check if Order Frequency exists and is linked
ORDER_FREQ_EXISTS="false"
FREQ_PER_DAY="0"
LINKED_CONCEPT_NAME=""

if [ "$CONCEPT_EXISTS" = "true" ]; then
    OF_RESP=$(openmrs_api_get "/orderfrequency?v=full")
    
    eval $(echo "$OF_RESP" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    results = data.get('results', [])
    found = False
    target_concept_uuid = '$CONCEPT_UUID' 
    for res in results:
        # Check if this OF links to our concept
        if res.get('concept', {}).get('uuid') == target_concept_uuid:
            print(f'ORDER_FREQ_EXISTS=true')
            print(f'FREQ_PER_DAY={res.get(\"frequencyPerDay\", 0)}')
            print(f'LINKED_CONCEPT_NAME=\"{res.get(\"concept\", {}).get(\"display\", \"\")}\"')
            found = True
            break
    if not found:
        print('ORDER_FREQ_EXISTS=false')
except Exception as e:
    print('ORDER_FREQ_EXISTS=false')
")
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "concept_exists": $CONCEPT_EXISTS,
    "concept_uuid": "$CONCEPT_UUID",
    "concept_class": "$CONCEPT_CLASS",
    "concept_datatype": "$CONCEPT_DATATYPE",
    "order_frequency_exists": $ORDER_FREQ_EXISTS,
    "frequency_per_day": $FREQ_PER_DAY,
    "linked_concept_name": "$LINKED_CONCEPT_NAME",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with read permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Exported result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="