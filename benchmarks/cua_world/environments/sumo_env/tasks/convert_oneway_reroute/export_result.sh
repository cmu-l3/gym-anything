#!/bin/bash
echo "=== Exporting convert_oneway_reroute results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
WORK_DIR="/home/ga/SUMO_Scenarios/bologna_acosta"
TARGET_EDGE=$(cat /tmp/target_edge.txt 2>/dev/null || echo "")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize tracking variables
NET_EXISTS="false"
NET_NEW="false"
EDGE_REMOVED="false"

ROU_EXISTS="false"
ROU_NEW="false"
HAS_VEHICLES="false"

CFG_EXISTS="false"
CFG_NEW="false"
CFG_VALID="false"

TRIP_EXISTS="false"
TRIP_NEW="false"
TRIP_COUNT="0"

# 1. Check Network File
if [ -f "$WORK_DIR/acosta_oneway.net.xml" ]; then
    NET_EXISTS="true"
    NET_MTIME=$(stat -c %Y "$WORK_DIR/acosta_oneway.net.xml" 2>/dev/null || echo "0")
    if [ "$NET_MTIME" -ge "$TASK_START" ]; then NET_NEW="true"; fi
    
    # Verify edge is gone
    if ! grep -q "id=\"$TARGET_EDGE\"" "$WORK_DIR/acosta_oneway.net.xml"; then
        EDGE_REMOVED="true"
    fi
fi

# 2. Check Route File
if [ -f "$WORK_DIR/acosta_oneway.rou.xml" ]; then
    ROU_EXISTS="true"
    ROU_MTIME=$(stat -c %Y "$WORK_DIR/acosta_oneway.rou.xml" 2>/dev/null || echo "0")
    if [ "$ROU_MTIME" -ge "$TASK_START" ]; then ROU_NEW="true"; fi
    
    # Check if duarouter actually populated it
    if grep -q "<vehicle" "$WORK_DIR/acosta_oneway.rou.xml"; then
        HAS_VEHICLES="true"
    fi
fi

# 3. Check Config File
if [ -f "$WORK_DIR/run_oneway.sumocfg" ]; then
    CFG_EXISTS="true"
    CFG_MTIME=$(stat -c %Y "$WORK_DIR/run_oneway.sumocfg" 2>/dev/null || echo "0")
    if [ "$CFG_MTIME" -ge "$TASK_START" ]; then CFG_NEW="true"; fi
    
    # Check if it references the new files
    if grep -q "acosta_oneway.net.xml" "$WORK_DIR/run_oneway.sumocfg" && \
       grep -q "acosta_oneway.rou.xml" "$WORK_DIR/run_oneway.sumocfg"; then
        CFG_VALID="true"
    fi
fi

# 4. Check Tripinfo File
if [ -f "$WORK_DIR/tripinfos_oneway.xml" ]; then
    TRIP_EXISTS="true"
    TRIP_MTIME=$(stat -c %Y "$WORK_DIR/tripinfos_oneway.xml" 2>/dev/null || echo "0")
    if [ "$TRIP_MTIME" -ge "$TASK_START" ]; then TRIP_NEW="true"; fi
    
    # Count completed trips
    TRIP_COUNT=$(grep -c "<tripinfo " "$WORK_DIR/tripinfos_oneway.xml" 2>/dev/null || echo "0")
fi

# Write results to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "target_edge": "$TARGET_EDGE",
    "network": {
        "exists": $NET_EXISTS,
        "created_during_task": $NET_NEW,
        "target_edge_removed": $EDGE_REMOVED
    },
    "routes": {
        "exists": $ROU_EXISTS,
        "created_during_task": $ROU_NEW,
        "has_vehicles": $HAS_VEHICLES
    },
    "config": {
        "exists": $CFG_EXISTS,
        "created_during_task": $CFG_NEW,
        "references_new_files": $CFG_VALID
    },
    "simulation": {
        "exists": $TRIP_EXISTS,
        "created_during_task": $TRIP_NEW,
        "completed_trips": $TRIP_COUNT
    }
}
EOF

# Move securely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="