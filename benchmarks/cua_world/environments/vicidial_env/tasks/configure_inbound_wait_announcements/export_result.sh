#!/bin/bash
set -e

echo "=== Exporting Inbound Wait Announcements Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the current configuration of TECH_SUPPORT
# We use docker exec to query the MySQL instance inside the container
echo "Querying database..."

QUERY="SELECT calculate_hold_time, hold_time_option, hold_time_seconds, hold_time_minimum, periodic_announce, periodic_announce_seconds FROM vicidial_inbound_groups WHERE group_id='TECH_SUPPORT' LIMIT 1"

# output format: tab-separated
DB_RESULT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -B -e "$QUERY" 2>/dev/null || echo "")

# Parse result into variables
# MySQL -B outputs tab separated values
read -r CALC_HOLD OPTION SECONDS MINIMUM PERIODIC P_SECONDS <<< "$DB_RESULT"

# Create JSON result
# Handle empty values safely
CALC_HOLD="${CALC_HOLD:-N}"
OPTION="${OPTION:-NONE}"
SECONDS="${SECONDS:-0}"
MINIMUM="${MINIMUM:-0}"
PERIODIC="${PERIODIC:-}"
P_SECONDS="${P_SECONDS:-0}"

# Get task timing
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
END_TIME=$(date +%s)

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "group_id": "TECH_SUPPORT",
    "actual_settings": {
        "calculate_hold_time": "$CALC_HOLD",
        "hold_time_option": "$OPTION",
        "hold_time_seconds": $SECONDS,
        "hold_time_minimum": $MINIMUM,
        "periodic_announce": "$PERIODIC",
        "periodic_announce_seconds": $P_SECONDS
    },
    "timestamp": $END_TIME,
    "task_duration": $((END_TIME - START_TIME))
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="