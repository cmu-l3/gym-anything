#!/bin/bash
echo "=== Exporting Pipeline Configuration Results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Functional Testing: Post a known value and read the feeds
# This verifies the logic actually works, regardless of the exact process list structure.
TEST_VAL=1000
APIKEY=$(get_apikey_write)

echo "Posting test value: $TEST_VAL Watts..."
curl -s "${EMONCMS_URL}/input/post?apikey=${APIKEY}&node=facility_meter&fulljson={\"main_incomer\":${TEST_VAL}}" > /dev/null
sleep 2 # Wait for processing

# 3. Fetch Feed Values
# Helper to get feed value by name
get_feed_val() {
    local fname="$1"
    local fid=$(db_query "SELECT id FROM feeds WHERE name='$fname'" 2>/dev/null | head -1)
    if [ -n "$fid" ]; then
        # Fetch last value
        curl -s "${EMONCMS_URL}/feed/value.json?apikey=${APIKEY}&id=${fid}"
    else
        echo "null"
    fi
}

VAL_POWER=$(get_feed_val "facility_power_W")
VAL_CARBON=$(get_feed_val "facility_carbon_kgph")
VAL_COST=$(get_feed_val "facility_cost_dollarsph")

# 4. Fetch Process List Configuration (for structural verification)
INPUT_ID=$(db_query "SELECT id FROM input WHERE nodeid='facility_meter' AND name='main_incomer'" 2>/dev/null | head -1)
PROCESS_LIST="{}"
if [ -n "$INPUT_ID" ]; then
    # Raw process list string from DB (e.g., "1:1,24:0,1:2...")
    RAW_PL=$(db_query "SELECT processList FROM input WHERE id=${INPUT_ID}" 2>/dev/null)
    PROCESS_LIST=$(python3 -c "import json; print(json.dumps('$RAW_PL'))")
fi

# 5. Check if Rate File was opened (anti-gaming heuristic)
FILE_ACCESSED="false"
# Simple check: is Firefox showing the text file? Or did they open it in a text editor?
# Hard to check strictly in docker env without auditd, but we can check if firefox history or generic process check.
# We'll skip strict file access check and rely on the math being correct (which requires the values).

# 6. Construct JSON Result
cat > /tmp/task_result.json << EOF
{
    "functional_test": {
        "input_value": $TEST_VAL,
        "feeds": {
            "facility_power_W": $VAL_POWER,
            "facility_carbon_kgph": $VAL_CARBON,
            "facility_cost_dollarsph": $VAL_COST
        }
    },
    "configuration": {
        "input_id": "$INPUT_ID",
        "process_list_raw": $PROCESS_LIST
    },
    "meta": {
        "timestamp": $(date +%s),
        "screenshot_path": "/tmp/task_final.png"
    }
}
EOF

# Permission fix
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json