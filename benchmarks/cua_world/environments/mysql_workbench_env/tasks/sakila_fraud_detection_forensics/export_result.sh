#!/bin/bash
# Export script for sakila_fraud_detection_forensics task

echo "=== Exporting Fraud Detection Results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
INJECTED=$(cat /tmp/injected_anomalies.json)

TIME_TRAVEL_ID=$(echo "$INJECTED" | python3 -c "import sys, json; print(json.load(sys.stdin)['time_travel_id'])")
NEPO_ID=$(echo "$INJECTED" | python3 -c "import sys, json; print(json.load(sys.stdin)['nepotism_id'])")
HOARDER_ID=$(echo "$INJECTED" | python3 -c "import sys, json; print(json.load(sys.stdin)['hoarder_id'])")

# 1. Check if View Exists and verify structure
VIEW_EXISTS=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM VIEWS WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='v_fraud_report';
")
VIEW_EXISTS=${VIEW_EXISTS:-0}

# 2. Check content of View (Query for injected IDs)
DETECTED_TIME_TRAVEL="false"
DETECTED_NEPOTISM="false"
DETECTED_HOARDING="false"
VIEW_HAS_COLUMNS="false"

if [ "$VIEW_EXISTS" -gt 0 ]; then
    # Check column names
    COLS=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
        SELECT GROUP_CONCAT(COLUMN_NAME) FROM COLUMNS WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='v_fraud_report';
    ")
    if [[ "$COLS" == *"fraud_type"* ]] && [[ "$COLS" == *"incident_id"* ]]; then
        VIEW_HAS_COLUMNS="true"
    fi

    # Verify Time Travel Detection
    TT_CHECK=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
        SELECT COUNT(*) FROM v_fraud_report 
        WHERE incident_id = $TIME_TRAVEL_ID AND fraud_type LIKE '%Time Travel%';
    ")
    if [ "${TT_CHECK:-0}" -gt 0 ]; then DETECTED_TIME_TRAVEL="true"; fi

    # Verify Nepotism Detection
    NEPO_CHECK=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
        SELECT COUNT(*) FROM v_fraud_report 
        WHERE incident_id = $NEPO_ID AND fraud_type LIKE '%Nepotism%';
    ")
    if [ "${NEPO_CHECK:-0}" -gt 0 ]; then DETECTED_NEPOTISM="true"; fi

    # Verify Hoarding Detection
    HOARD_CHECK=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
        SELECT COUNT(*) FROM v_fraud_report 
        WHERE incident_id = $HOARDER_ID AND fraud_type LIKE '%Hoarding%';
    ")
    if [ "${HOARD_CHECK:-0}" -gt 0 ]; then DETECTED_HOARDING="true"; fi
fi

# 3. Check CSV Export
CSV_FILE="/home/ga/Documents/exports/fraud_report.csv"
CSV_EXISTS="false"
CSV_ROWS=0
CSV_MTIME=0

if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV_FILE")
    CSV_ROWS=$(wc -l < "$CSV_FILE")
    # Decrement for header
    CSV_ROWS=$((CSV_ROWS - 1))
fi

# 4. App Running Check
APP_RUNNING="false"
if pgrep -f "mysql-workbench" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "view_exists": $VIEW_EXISTS,
    "view_has_columns": $VIEW_HAS_COLUMNS,
    "detected_time_travel": $DETECTED_TIME_TRAVEL,
    "detected_nepotism": $DETECTED_NEPOTISM,
    "detected_hoarding": $DETECTED_HOARDING,
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "csv_mtime": $CSV_MTIME,
    "task_start_time": $TASK_START,
    "app_running": $APP_RUNNING
}
EOF

echo "Export complete. Result:"
cat /tmp/task_result.json