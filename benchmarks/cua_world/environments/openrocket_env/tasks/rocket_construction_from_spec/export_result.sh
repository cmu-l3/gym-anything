#!/bin/bash
# Export script for rocket_construction_from_spec task
# Extracts metadata about the saved file for verification.

echo "=== Exporting rocket_construction_from_spec result ==="

source /workspace/scripts/task_utils.sh || exit 1

# Take final screenshot showing completed rocket design
take_screenshot /tmp/task_final.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/phoenix_scout.ork"
START_TIME_FILE="/tmp/task_start_time.txt"

ork_exists="false"
ork_size=0
ork_mtime=0
task_start_ts=0

# Read task start time
if [ -f "$START_TIME_FILE" ]; then
    task_start_ts=$(cat "$START_TIME_FILE" | grep task_start_ts | cut -d'=' -f2)
fi

# Check if agent created the file
if [ -f "$ORK_FILE" ]; then
    ork_exists="true"
    ork_size=$(stat -c %s "$ORK_FILE" 2>/dev/null)
    ork_mtime=$(stat -c %Y "$ORK_FILE" 2>/dev/null)
fi

# Write result variables to a JSON object for the verifier
write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_size\": $ork_size,
  \"ork_mtime\": $ork_mtime,
  \"task_start_ts\": ${task_start_ts:-0}
}" /tmp/task_result.json

echo "Result JSON saved to /tmp/task_result.json"
echo "=== Export complete ==="