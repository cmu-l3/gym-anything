#!/bin/bash
echo "=== Exporting model_passenger_transit_transfer result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Capture final state screenshot
take_screenshot /tmp/task_final.png

# Define expected paths
OUTPUT_DIR="/home/ga/SUMO_Output"
ROU_FILE="$OUTPUT_DIR/commuters.rou.xml"
CFG_FILE="$OUTPUT_DIR/run_commuters.sumocfg"
TRIP_FILE="$OUTPUT_DIR/tripinfo.xml"

ROU_EXISTS="false"
CFG_EXISTS="false"
TRIP_EXISTS="false"
SIM_SUCCESS="false"

# Check file existence
if [ -f "$ROU_FILE" ]; then ROU_EXISTS="true"; fi
if [ -f "$CFG_FILE" ]; then CFG_EXISTS="true"; fi
if [ -f "$TRIP_FILE" ]; then TRIP_EXISTS="true"; fi

# Anti-gaming verification execution: 
# Run the simulation directly using the user's config file to ensure it's valid
# and actually produces the claimed outputs.
rm -f /tmp/verifier_tripinfo.xml
if [ "$CFG_EXISTS" = "true" ]; then
    echo "Running verification simulation to validate sumocfg..."
    su - ga -c "SUMO_HOME=/usr/share/sumo sumo -c $CFG_FILE --tripinfo-output /tmp/verifier_tripinfo.xml --no-step-log true" > /tmp/verifier_sumo.log 2>&1
    
    # Check if SUMO executed successfully and produced the verification tripinfo
    if [ $? -eq 0 ] && [ -f /tmp/verifier_tripinfo.xml ]; then
        SIM_SUCCESS="true"
        echo "Verification simulation succeeded."
    else
        echo "Verification simulation failed or produced no output."
    fi
fi

# Create export JSON file securely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "rou_exists": $ROU_EXISTS,
    "cfg_exists": $CFG_EXISTS,
    "trip_exists": $TRIP_EXISTS,
    "sim_success": $SIM_SUCCESS
}
EOF

# Move to standard location and fix permissions
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# Ensure verifier outputs are readable by the Python verifier script
chmod 666 /tmp/verifier_tripinfo.xml 2>/dev/null || true

echo "=== Export complete ==="