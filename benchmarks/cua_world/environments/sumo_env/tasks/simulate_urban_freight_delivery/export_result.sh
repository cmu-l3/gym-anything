#!/bin/bash
echo "=== Exporting simulate_urban_freight_delivery result ==="

source /workspace/scripts/task_utils.sh

# Take final state screenshot
take_screenshot /tmp/task_final.png

SCENARIO_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"
OUTPUT_DIR="/home/ga/SUMO_Output"

# Check file existence and copy to /tmp for verifier access
HAS_FREIGHT_XML="false"
if [ -f "$SCENARIO_DIR/pasubio_freight.rou.xml" ]; then
    HAS_FREIGHT_XML="true"
    cp "$SCENARIO_DIR/pasubio_freight.rou.xml" /tmp/pasubio_freight.rou.xml
    chmod 666 /tmp/pasubio_freight.rou.xml
fi

HAS_CONFIG="false"
if [ -f "$SCENARIO_DIR/run.sumocfg" ]; then
    HAS_CONFIG="true"
    cp "$SCENARIO_DIR/run.sumocfg" /tmp/run.sumocfg
    chmod 666 /tmp/run.sumocfg
fi

HAS_TRIPINFOS="false"
if [ -f "$SCENARIO_DIR/tripinfos.xml" ]; then
    HAS_TRIPINFOS="true"
    cp "$SCENARIO_DIR/tripinfos.xml" /tmp/tripinfos.xml
    chmod 666 /tmp/tripinfos.xml
fi

HAS_REPORT="false"
if [ -f "$OUTPUT_DIR/freight_report.txt" ]; then
    HAS_REPORT="true"
    cp "$OUTPUT_DIR/freight_report.txt" /tmp/freight_report.txt
    chmod 666 /tmp/freight_report.txt
fi

# Export result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "has_freight_xml": $HAS_FREIGHT_XML,
    "has_config": $HAS_CONFIG,
    "has_tripinfos": $HAS_TRIPINFOS,
    "has_report": $HAS_REPORT,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="