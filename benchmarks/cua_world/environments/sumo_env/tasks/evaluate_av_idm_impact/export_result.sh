#!/bin/bash
echo "=== Exporting evaluate_av_idm_impact result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check creation/mtime of important files
get_mtime() {
    stat -c %Y "$1" 2>/dev/null || echo "0"
}

BASE_XML="/home/ga/SUMO_Output/tripinfos_baseline.xml"
AV_XML="/home/ga/SUMO_Output/tripinfos_av.xml"
COMP_TXT="/home/ga/SUMO_Output/av_comparison.txt"

BASE_MTIME=$(get_mtime "$BASE_XML")
AV_MTIME=$(get_mtime "$AV_XML")
COMP_MTIME=$(get_mtime "$COMP_TXT")

# Copy the generated output files to /tmp so verifier can access them easily
cp "$BASE_XML" /tmp/tripinfos_baseline.xml 2>/dev/null || true
cp "$AV_XML" /tmp/tripinfos_av.xml 2>/dev/null || true
cp "$COMP_TXT" /tmp/av_comparison.txt 2>/dev/null || true

# Archive the scenario directory so verifier can inspect modified config and vTypes
cd /home/ga/SUMO_Scenarios
tar -czf /tmp/bologna_acosta_scenario.tar.gz bologna_acosta/

# Write metadata to result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "baseline_xml_mtime": $BASE_MTIME,
    "av_xml_mtime": $AV_MTIME,
    "comparison_txt_mtime": $COMP_MTIME,
    "baseline_xml_exists": $([ -f "$BASE_XML" ] && echo "true" || echo "false"),
    "av_xml_exists": $([ -f "$AV_XML" ] && echo "true" || echo "false"),
    "comparison_txt_exists": $([ -f "$COMP_TXT" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"
chmod 666 /tmp/tripinfos_baseline.xml /tmp/tripinfos_av.xml /tmp/av_comparison.txt /tmp/bologna_acosta_scenario.tar.gz 2>/dev/null || true

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="