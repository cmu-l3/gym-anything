#!/bin/bash
echo "=== Exporting Result ==="

source /workspace/scripts/task_utils.sh

# Capture screenshot of final state for VLM potential
take_screenshot /tmp/task_final.png

WORK_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"
POLY_FILE="$WORK_DIR/pasubio_polygons.add.xml"
CONFIG_FILE="$WORK_DIR/run_enriched.sumocfg"

POLY_EXISTS="false"
POLY_COUNT=0
HAS_TYPE="false"
IS_PROJECTED="false"

CONFIG_EXISTS="false"
CONFIG_INCLUDES_POLY="false"
SIM_RUNS="false"

# 1. Inspect the generated spatial geometry file
if [ -f "$POLY_FILE" ]; then
    POLY_EXISTS="true"
    
    # Check for valid nodes (closed shapes or POIs)
    POLY_COUNT=$(grep -E -c "<poly |<poi " "$POLY_FILE" || echo "0")
    
    # If the user correctly included the typemap, shapes should possess 'type' attributes
    if grep -q 'type=".*"' "$POLY_FILE"; then
        HAS_TYPE="true"
    fi
    
    # 2. Check if a valid cartesian projection was applied
    # By querying the X-value of the first shape logic
    FIRST_SHAPE=$(grep -o 'shape="[^"]*"' "$POLY_FILE" | head -1 | cut -d'"' -f2)
    if [ -n "$FIRST_SHAPE" ]; then
        FIRST_COORD=$(echo "$FIRST_SHAPE" | cut -d' ' -f1)
        X_VAL=$(echo "$FIRST_COORD" | cut -d',' -f1)
        
        # Validate floating point
        if [[ $X_VAL =~ ^[+-]?[0-9]+\.?[0-9]*$ ]]; then
            # If the value exceeds realistic WGS84 lat/lon constraints (+/- 100), the network file offset was correctly applied
            IS_LARGE=$(echo "$X_VAL" | awk '{if ($1 > 100 || $1 < -100) print "true"; else print "false"}')
            if [ "$IS_LARGE" = "true" ]; then
                IS_PROJECTED="true"
            fi
        fi
    fi
fi

# 3. Check and dry-run the modified configuration
if [ -f "$CONFIG_FILE" ]; then
    CONFIG_EXISTS="true"
    
    # Is the user actually calling the new additional file?
    if grep -q 'pasubio_polygons.add.xml' "$CONFIG_FILE"; then
        CONFIG_INCLUDES_POLY="true"
    fi
    
    # Run a headless integration check for 5 steps to verify the config's overall integrity didn't crash
    su - ga -c "SUMO_HOME=/usr/share/sumo sumo -c $CONFIG_FILE --steps 5 > /tmp/sim_test.log 2>&1"
    if [ $? -eq 0 ]; then
        SIM_RUNS="true"
    fi
fi

# Package context outputs for the verifier framework
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "poly_exists": $POLY_EXISTS,
    "poly_count": $POLY_COUNT,
    "has_type": $HAS_TYPE,
    "is_projected": $IS_PROJECTED,
    "config_exists": $CONFIG_EXISTS,
    "config_includes_poly": $CONFIG_INCLUDES_POLY,
    "sim_runs": $SIM_RUNS
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="