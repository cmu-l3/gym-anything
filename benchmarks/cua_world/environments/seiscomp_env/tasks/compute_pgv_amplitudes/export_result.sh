#!/bin/bash
echo "=== Exporting compute_pgv_amplitudes result ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check PGV in Database
echo "--- Checking Database for PGV Amplitudes ---"
PGV_DB_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Amplitude WHERE type='PGV'" 2>/dev/null || echo "0")
echo "PGV Count in DB: $PGV_DB_COUNT"

# Export sample DB records for content verification
seiscomp_db_query "SELECT waveformID_stationCode, value_value FROM Amplitude WHERE type='PGV' LIMIT 50" > /tmp/pgv_db_samples.txt 2>/dev/null || true
chmod 644 /tmp/pgv_db_samples.txt 2>/dev/null || true

# 2. Check scamp configuration
echo "--- Checking scamp configuration ---"
CONFIG_HAS_PGV="false"
if grep -qi "PGV" "$SEISCOMP_ROOT/etc/"*.cfg 2>/dev/null; then
    CONFIG_HAS_PGV="true"
fi
echo "Config has PGV: $CONFIG_HAS_PGV"

# 3. Check CSV Report
echo "--- Checking CSV Report ---"
CSV_PATH="/home/ga/Documents/pgv_report.csv"
CSV_EXISTS="false"
CSV_MODIFIED_DURING_TASK="false"
CSV_SIZE=0

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c%s "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_MTIME=$(stat -c%Y "$CSV_PATH" 2>/dev/null || echo "0")
    
    if [ "$CSV_MTIME" -ge "$TASK_START" ]; then
        CSV_MODIFIED_DURING_TASK="true"
    fi
    
    # Copy to /tmp so verifier can easily retrieve it
    cp "$CSV_PATH" /tmp/pgv_report.csv
    chmod 644 /tmp/pgv_report.csv
fi

echo "CSV Exists: $CSV_EXISTS"
echo "CSV Size: $CSV_SIZE"

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "pgv_db_count": $PGV_DB_COUNT,
    "config_has_pgv": $CONFIG_HAS_PGV,
    "csv_exists": $CSV_EXISTS,
    "csv_modified_during_task": $CSV_MODIFIED_DURING_TASK,
    "csv_size_bytes": $CSV_SIZE
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="