#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh || exit 1

take_screenshot /tmp/task_final.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/payload_lofter.ork"
REPORT_FILE="/home/ga/Documents/exports/expansion_report.txt"

ork_exists="false"
report_exists="false"

# Check for the exact file, or the newest modified .ork file if they misnamed it
if [ -f "$ORK_FILE" ]; then
    ork_exists="true"
else
    # Fallback to newest .ork file
    NEWEST_ORK=$(ls -t /home/ga/Documents/rockets/*.ork 2>/dev/null | head -1)
    if [ -n "$NEWEST_ORK" ] && [ "$NEWEST_ORK" != "/home/ga/Documents/rockets/simple_model_rocket.ork" ]; then
        cp "$NEWEST_ORK" "$ORK_FILE"
        ork_exists="true"
    fi
fi

if [ -f "$REPORT_FILE" ]; then
    report_exists="true"
else
    # Fallback to newest txt in exports
    NEWEST_TXT=$(ls -t /home/ga/Documents/exports/*.txt 2>/dev/null | head -1)
    if [ -n "$NEWEST_TXT" ]; then
        cp "$NEWEST_TXT" "$REPORT_FILE"
        report_exists="true"
    fi
fi

ork_size=0
report_size=0
[ "$ork_exists" = "true" ] && ork_size=$(stat -c %s "$ORK_FILE" 2>/dev/null)
[ "$report_exists" = "true" ] && report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)

write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_size\": $ork_size,
  \"report_exists\": $report_exists,
  \"report_size\": $report_size
}" /tmp/task_result.json

echo "=== Export complete ==="