#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the test records
echo "Querying final state of test records..."

# Create a JSON dump of the relevant fields for our test GUIDs
# structure: { "TEST-DIRTY-001": {"addr": "...", "tel": "..."}, ... }

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Start JSON object
echo "{" > "$TEMP_JSON"
echo "  \"task_timestamp\": \"$(date -Iseconds)\"," >> "$TEMP_JSON"
echo "  \"records\": {" >> "$TEMP_JSON"

# Loop through our known test GUIDs
GUIDS=("TEST-DIRTY-001" "TEST-DIRTY-002" "TEST-DIRTY-003" "TEST-CLEAN-001")
LEN=${#GUIDS[@]}

for (( i=0; i<$LEN; i++ )); do
    GUID="${GUIDS[$i]}"
    
    # Query MySQL for Address and Tel1
    # Use -N (skip headers) and -B (batch/tab-separated)
    # Use sed to escape quotes for valid JSON
    DATA=$(mysql -u root DrTuxTest -N -B -e "SELECT FchPat_Adresse, IFNULL(FchPat_Tel1, '') FROM fchpat WHERE FchPat_GUID_Doss='$GUID'")
    
    ADDR=$(echo "$DATA" | cut -f1 | sed 's/"/\\"/g' | sed 's/	/ /g') # simplistic tab handling
    TEL=$(echo "$DATA" | cut -f2 | sed 's/"/\\"/g')
    
    echo "    \"$GUID\": {" >> "$TEMP_JSON"
    echo "      \"address\": \"$ADDR\"," >> "$TEMP_JSON"
    echo "      \"phone\": \"$TEL\"" >> "$TEMP_JSON"
    
    if [ $i -lt $(($LEN - 1)) ]; then
        echo "    }," >> "$TEMP_JSON"
    else
        echo "    }" >> "$TEMP_JSON"
    fi
done

echo "  }" >> "$TEMP_JSON"
echo "}" >> "$TEMP_JSON"

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json:"
cat /tmp/task_result.json

echo "=== Export complete ==="