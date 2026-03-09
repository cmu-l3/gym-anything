#!/bin/bash
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RISK_LEVEL=$(cat /tmp/.task_risk_level 2>/dev/null || echo "0")
CASE_ID=$(cat /tmp/target_case_id.txt 2>/dev/null)

# 3. Retrieve Case Participants via API
# We need to see who was added to the case
echo "Fetching case participants..."
if [ -n "$CASE_ID" ]; then
    # Usually participants are a sub-resource or part of the full object
    # We'll fetch the full case and looking for 'participants' list
    CASE_DATA=$(arkcase_api GET "plugin/complaint/$CASE_ID")
else
    # Fallback: Search for the case by title if ID failed
    echo "Searching for case by title..."
    SEARCH_RES=$(arkcase_api GET "plugin/complaint?title=Disturbance%20at%20Central%20Plaza")
    # This is a simplification; actual search API might differ. 
    # Assuming we have the ID from setup is safer.
    CASE_DATA="{}" 
fi

# 4. Save API Response for Verifier
echo "$CASE_DATA" > /tmp/final_case_data.json

# 5. Check Browser URL to see if they visited People module (Heuristic)
# This is hard to get reliably from shell without browser automation tools hooked in,
# but we can check if the VLM screenshots will show it.
# We will leave strict navigation verification to VLM.

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "risk_level_ground_truth": $RISK_LEVEL,
    "case_id": "$CASE_ID",
    "final_screenshot_path": "/tmp/task_final.png",
    "case_data_dump_path": "/tmp/final_case_data.json"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"