#!/bin/bash
echo "=== Setting up manage_holiday_calendar task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for Sentrifugo to be accessible
wait_for_http "$SENTRIFUGO_URL" 60

CURRENT_YEAR=$(date +%Y)

# Record baseline holiday count
BASELINE_COUNT=$(get_holiday_count)
log "Baseline holiday count for ${CURRENT_YEAR}: $BASELINE_COUNT"

# Ensure 'Veterans Day' does NOT exist for this year (cleanup from prior run)
sentrifugo_db_root_query "DELETE FROM main_holidaydates WHERE holidayname='Veterans Day' AND holidayyear=${CURRENT_YEAR};" 2>/dev/null || true

# Save baseline data for verification
safe_write_result "{\"baseline_holiday_count\": ${BASELINE_COUNT:-0}, \"target_year\": ${CURRENT_YEAR}}" /tmp/task_baseline.json

# Log in and navigate to Holiday Dates page
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/holidaydates"

# Take screenshot of starting state
sleep 3
take_screenshot /tmp/task_start_screenshot.png

log "Task start state ready: Holiday Dates page visible"
echo "=== manage_holiday_calendar task setup complete ==="
