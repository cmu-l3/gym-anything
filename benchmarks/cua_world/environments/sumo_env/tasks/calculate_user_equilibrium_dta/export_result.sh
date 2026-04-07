#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

STUDY_DIR="/home/ga/SUMO_Output/dta_study"
DEMAND_FILE="${STUDY_DIR}/demand.trips.xml"
ITER_004="${STUDY_DIR}/004"

STUDY_DIR_EXISTS="false"
if [ -d "$STUDY_DIR" ]; then
    STUDY_DIR_EXISTS="true"
fi

DEMAND_EXISTS="false"
DEMAND_MTIME=0
TRIPS_COUNT=0
if [ -f "$DEMAND_FILE" ]; then
    DEMAND_EXISTS="true"
    DEMAND_MTIME=$(stat -c %Y "$DEMAND_FILE" 2>/dev/null || echo "0")
    # Count <trip> or <vehicle> tags to determine number of generated trips
    TRIPS_COUNT=$(grep -c -E "<trip|<vehicle" "$DEMAND_FILE" 2>/dev/null || echo "0")
fi

FOLDERS_EXIST="false"
if [ -d "${STUDY_DIR}/000" ] && [ -d "${STUDY_DIR}/001" ] && \
   [ -d "${STUDY_DIR}/002" ] && [ -d "${STUDY_DIR}/003" ] && \
   [ -d "${STUDY_DIR}/004" ]; then
    FOLDERS_EXIST="true"
fi

ROU_ALT_EXISTS="false"
ROU_ALT_MTIME=0
ROUTE_DIST_COUNT=0
if [ -d "$ITER_004" ]; then
    # Find the output routes file (often named something like acosta_buslanes_004.rou.alt.xml)
    ROU_ALT_FILE=$(ls "${ITER_004}/"*.rou.alt.xml 2>/dev/null | head -1)
    if [ -n "$ROU_ALT_FILE" ] && [ -f "$ROU_ALT_FILE" ]; then
        ROU_ALT_EXISTS="true"
        ROU_ALT_MTIME=$(stat -c %Y "$ROU_ALT_FILE" 2>/dev/null || echo "0")
        # Ensure that it generated multi-path routeDistributions, a key sign of DTA equilibrium
        ROUTE_DIST_COUNT=$(grep -c "<routeDistribution" "$ROU_ALT_FILE" 2>/dev/null || echo "0")
    fi
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "study_dir_exists": $STUDY_DIR_EXISTS,
    "demand_exists": $DEMAND_EXISTS,
    "demand_mtime": $DEMAND_MTIME,
    "trips_count": $TRIPS_COUNT,
    "folders_exist": $FOLDERS_EXIST,
    "rou_alt_exists": $ROU_ALT_EXISTS,
    "rou_alt_mtime": $ROU_ALT_MTIME,
    "route_dist_count": $ROUTE_DIST_COUNT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="