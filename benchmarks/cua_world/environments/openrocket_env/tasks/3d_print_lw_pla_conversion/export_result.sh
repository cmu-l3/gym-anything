#!/bin/bash
# Export script for 3d_print_lw_pla_conversion task

echo "=== Exporting 3d_print_lw_pla_conversion result ==="
source /workspace/scripts/task_utils.sh || exit 1

# Take final screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/janus_lw_pla.ork"
REPORT_FILE="/home/ga/Documents/exports/lw_pla_report.txt"

ork_exists="false"
report_exists="false"
[ -f "$ORK_FILE" ] && ork_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

ork_size=0
report_size=0
ork_mtime=0
[ -f "$ORK_FILE" ] && ork_size=$(stat -c %s "$ORK_FILE" 2>/dev/null)
[ -f "$REPORT_FILE" ] && report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)
[ -f "$ORK_FILE" ] && ork_mtime=$(stat -c %Y "$ORK_FILE" 2>/dev/null)

# Verify OpenRocket is running
app_running="false"
if pgrep -f "OpenRocket.jar" > /dev/null; then
    app_running="true"
fi

# Write results
write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_size\": $ork_size,
  \"ork_mtime\": $ork_mtime,
  \"report_exists\": $report_exists,
  \"report_size\": $report_size,
  \"app_running\": $app_running
}" /tmp/task_result.json

echo "=== Export complete ==="