#!/bin/bash
echo "=== Exporting evaluate_road_diet_lane_reduction result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check if required files exist
REPORT_EXISTS="false"
PATCH_EXISTS="false"
NEW_NET_EXISTS="false"
BASELINE_TRIPINFO_EXISTS="false"
DIET_TRIPINFO_EXISTS="false"

if [ -f /home/ga/SUMO_Output/road_diet_report.txt ]; then REPORT_EXISTS="true"; fi
if [ -f /home/ga/SUMO_Output/roaddiet.edg.xml ]; then PATCH_EXISTS="true"; fi
if [ -f /home/ga/SUMO_Output/acosta_roaddiet.net.xml ]; then NEW_NET_EXISTS="true"; fi
if [ -f /home/ga/SUMO_Output/baseline_tripinfo.xml ]; then BASELINE_TRIPINFO_EXISTS="true"; fi
if [ -f /home/ga/SUMO_Output/roaddiet_tripinfo.xml ]; then DIET_TRIPINFO_EXISTS="true"; fi

# Extract report content for verifier (replace newlines with pipes, handle dos endings)
REPORT_CONTENT=""
if [ "$REPORT_EXISTS" = "true" ]; then
    REPORT_CONTENT=$(cat /home/ga/SUMO_Output/road_diet_report.txt | tr -d '\r' | tr '\n' '|' | sed 's/"/\\"/g')
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "patch_exists": $PATCH_EXISTS,
    "new_net_exists": $NEW_NET_EXISTS,
    "baseline_tripinfo_exists": $BASELINE_TRIPINFO_EXISTS,
    "diet_tripinfo_exists": $DIET_TRIPINFO_EXISTS,
    "report_content": "$REPORT_CONTENT"
}
EOF

# Make copies of the outputs to /tmp for verifier to pull
cp /home/ga/SUMO_Output/roaddiet.edg.xml /tmp/roaddiet.edg.xml 2>/dev/null || true
cp /home/ga/SUMO_Output/acosta_roaddiet.net.xml /tmp/acosta_roaddiet.net.xml 2>/dev/null || true
cp /home/ga/SUMO_Output/baseline_tripinfo.xml /tmp/baseline_tripinfo.xml 2>/dev/null || true
cp /home/ga/SUMO_Output/roaddiet_tripinfo.xml /tmp/roaddiet_tripinfo.xml 2>/dev/null || true
# Get original network to parse in the verifier
cp /home/ga/SUMO_Scenarios/bologna_acosta/acosta_buslanes.net.xml /tmp/original.net.xml 2>/dev/null || true

# Export result safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="