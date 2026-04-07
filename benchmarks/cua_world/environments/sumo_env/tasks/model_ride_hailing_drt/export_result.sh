#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Copy files to /tmp for the verifier to safely read via copy_from_env
# We use prefixes to avoid namespace collisions in /tmp
cp /home/ga/SUMO_Output/drt_demand.rou.xml /tmp/drt_demand.rou.xml 2>/dev/null || true
cp /home/ga/SUMO_Output/ride_hailing.sumocfg /tmp/ride_hailing.sumocfg 2>/dev/null || true
cp /home/ga/SUMO_Output/tripinfo.xml /tmp/tripinfo.xml 2>/dev/null || true
cp /home/ga/SUMO_Output/avg_wait_time.txt /tmp/avg_wait_time.txt 2>/dev/null || true
chmod 666 /tmp/drt_demand.rou.xml /tmp/ride_hailing.sumocfg /tmp/tripinfo.xml /tmp/avg_wait_time.txt 2>/dev/null || true

# Check what was created
DEMAND_EXISTS=$([ -f /tmp/drt_demand.rou.xml ] && echo "true" || echo "false")
CONFIG_EXISTS=$([ -f /tmp/ride_hailing.sumocfg ] && echo "true" || echo "false")
TRIPINFO_EXISTS=$([ -f /tmp/tripinfo.xml ] && echo "true" || echo "false")
ANALYSIS_EXISTS=$([ -f /tmp/avg_wait_time.txt ] && echo "true" || echo "false")

# Extract file creation timestamps
DEMAND_MTIME=$([ "$DEMAND_EXISTS" = "true" ] && stat -c %Y /tmp/drt_demand.rou.xml || echo "0")
CONFIG_MTIME=$([ "$CONFIG_EXISTS" = "true" ] && stat -c %Y /tmp/ride_hailing.sumocfg || echo "0")
TRIPINFO_MTIME=$([ "$TRIPINFO_EXISTS" = "true" ] && stat -c %Y /tmp/tripinfo.xml || echo "0")

# Write metadata JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "demand_exists": $DEMAND_EXISTS,
    "demand_mtime": $DEMAND_MTIME,
    "config_exists": $CONFIG_EXISTS,
    "config_mtime": $CONFIG_MTIME,
    "tripinfo_exists": $TRIPINFO_EXISTS,
    "tripinfo_mtime": $TRIPINFO_MTIME,
    "analysis_exists": $ANALYSIS_EXISTS
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result metadata saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="