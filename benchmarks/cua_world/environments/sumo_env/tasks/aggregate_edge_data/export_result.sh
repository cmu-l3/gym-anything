#!/bin/bash
echo "=== Exporting aggregate_edge_data result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check and stage edge meandata XML
XML_EXISTS="false"
XML_CREATED_DURING_TASK="false"
XML_SIZE=0

if [ -f "/home/ga/SUMO_Output/edge_meandata.xml" ]; then
    XML_EXISTS="true"
    XML_SIZE=$(stat -c %s "/home/ga/SUMO_Output/edge_meandata.xml" 2>/dev/null || echo "0")
    XML_MTIME=$(stat -c %Y "/home/ga/SUMO_Output/edge_meandata.xml" 2>/dev/null || echo "0")
    
    if [ "$XML_MTIME" -ge "$TASK_START" ]; then
        XML_CREATED_DURING_TASK="true"
    fi
    
    # Copy to /tmp for verifier
    cp "/home/ga/SUMO_Output/edge_meandata.xml" /tmp/edge_meandata.xml
    chmod 666 /tmp/edge_meandata.xml
fi

# Check and stage congestion report text
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_SIZE=0

if [ -f "/home/ga/SUMO_Output/congestion_report.txt" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "/home/ga/SUMO_Output/congestion_report.txt" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "/home/ga/SUMO_Output/congestion_report.txt" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    # Copy to /tmp for verifier
    cp "/home/ga/SUMO_Output/congestion_report.txt" /tmp/congestion_report.txt
    chmod 666 /tmp/congestion_report.txt
fi

# Check if config was modified
CONFIG_MODIFIED="false"
if grep -qi "meandata\|edgedata" /home/ga/SUMO_Scenarios/bologna_pasubio/*.sumocfg 2>/dev/null || \
   grep -qi "meandata\|edgedata" /home/ga/SUMO_Scenarios/bologna_pasubio/*.add.xml 2>/dev/null; then
    CONFIG_MODIFIED="true"
fi

# Export stats to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "xml_exists": $XML_EXISTS,
    "xml_created_during_task": $XML_CREATED_DURING_TASK,
    "xml_size_bytes": $XML_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_size_bytes": $REPORT_SIZE,
    "config_modified": $CONFIG_MODIFIED
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="