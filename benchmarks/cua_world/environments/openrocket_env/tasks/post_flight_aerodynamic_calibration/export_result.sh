#!/bin/bash
echo "=== Exporting post_flight_aerodynamic_calibration result ==="
source /workspace/scripts/task_utils.sh || exit 1

# Capture final visual state
take_screenshot /tmp/calibration_final.png 2>/dev/null || true

# Define paths
ORK_FILE="/home/ga/Documents/rockets/calibrated_rocket.ork"
CALIB_CSV="/home/ga/Documents/exports/calibration_flight.csv"
PREDICT_CSV="/home/ga/Documents/exports/prediction_flight.csv"
REPORT_FILE="/home/ga/Documents/exports/calibration_report.txt"

ork_exists="false"
calib_csv_exists="false"
predict_csv_exists="false"
report_exists="false"

[ -f "$ORK_FILE" ] && ork_exists="true"
[ -f "$CALIB_CSV" ] && calib_csv_exists="true"
[ -f "$PREDICT_CSV" ] && predict_csv_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

ork_mtime=0
report_size=0

[ -f "$ORK_FILE" ] && ork_mtime=$(stat -c %Y "$ORK_FILE" 2>/dev/null)
[ -f "$REPORT_FILE" ] && report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)

# Save result payload for verifier
write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_mtime\": \"$ork_mtime\",
  \"calib_csv_exists\": $calib_csv_exists,
  \"predict_csv_exists\": $predict_csv_exists,
  \"report_exists\": $report_exists,
  \"report_size\": $report_size
}" /tmp/calibration_result.json

echo "=== Export complete ==="