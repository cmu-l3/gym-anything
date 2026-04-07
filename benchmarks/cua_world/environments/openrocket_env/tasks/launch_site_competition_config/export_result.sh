#!/bin/bash
echo "=== Exporting launch_site_competition_config result ==="

source /workspace/scripts/task_utils.sh || exit 1

# Take final screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

# Define target paths
TARGET_ORK="/home/ga/Documents/rockets/competition_ready.ork"
BRIEFING_TXT="/home/ga/Documents/exports/pre_launch_briefing.txt"
STARTING_MD5=$(cat /tmp/starting_ork_md5.txt 2>/dev/null || echo "unknown")

# Check outputs
ork_exists="false"
briefing_exists="false"
ork_md5="none"
ork_size=0
briefing_size=0

if [ -f "$TARGET_ORK" ]; then
    ork_exists="true"
    ork_md5=$(md5sum "$TARGET_ORK" | awk '{print $1}')
    ork_size=$(stat -c %s "$TARGET_ORK" 2>/dev/null)
fi

if [ -f "$BRIEFING_TXT" ]; then
    briefing_exists="true"
    briefing_size=$(stat -c %s "$BRIEFING_TXT" 2>/dev/null)
fi

# Write summary JSON for quick checks
write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_md5\": \"$ork_md5\",
  \"ork_size\": $ork_size,
  \"briefing_exists\": $briefing_exists,
  \"briefing_size\": $briefing_size,
  \"starting_md5\": \"$STARTING_MD5\",
  \"task_end_time\": $(date +%s)
}" /tmp/task_result.json

echo "Export summary saved."
echo "=== Export complete ==="