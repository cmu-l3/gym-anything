#!/bin/bash
echo "=== Exporting simulation_timestep_sensitivity_study result ==="
source /workspace/scripts/task_utils.sh || exit 1

take_screenshot /tmp/sensitivity_final.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/sensitivity_study.ork"
EXPORTS_DIR="/home/ga/Documents/exports"
REPORT_FILE="$EXPORTS_DIR/sensitivity_report.txt"

ork_exists="false"
report_exists="false"
[ -f "$ORK_FILE" ] && ork_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

# Collect stats on exported CSV files for anti-gaming checks
csv_count=$(ls "$EXPORTS_DIR"/*.csv 2>/dev/null | wc -l)
csv_stats="[]"

if [ "$csv_count" -gt 0 ]; then
    # Generate JSON array of file line counts using awk
    csv_stats="["$(find "$EXPORTS_DIR" -maxdepth 1 -name "*.csv" -exec wc -l {} \; | awk '{print "{\"file\": \"" $2 "\", \"lines\": " $1 "}"}' | paste -sd "," -)"]"
fi

report_size=0
[ -f "$REPORT_FILE" ] && report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)

write_result_json "{
  \"ork_exists\": $ork_exists,
  \"report_exists\": $report_exists,
  \"report_size\": $report_size,
  \"csv_count\": $csv_count,
  \"csv_stats\": $csv_stats
}" /tmp/sensitivity_result.json

echo "=== Export complete ==="