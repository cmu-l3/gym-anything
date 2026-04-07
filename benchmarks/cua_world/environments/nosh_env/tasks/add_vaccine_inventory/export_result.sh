#!/bin/bash
echo "=== Exporting add_vaccine_inventory results ==="

# 1. Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Query Database for the Inventory Record
#    We look for the specific Lot Number 'FL-2026-QA'.
#    We query the 'vaccine_inventory' table, falling back to 'inventory' if needed.

echo "Querying NOSH database for lot FL-2026-QA..."

# Attempt 1: vaccine_inventory table (Standard for many NOSH versions)
# Selecting typical columns: id, vaccine_id/cvx, lot_number, expiration_date, quantity/on_hand
DB_RESULT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT lot_number, expiration_date, quantity, cvx_code, manufacturer 
     FROM vaccine_inventory 
     WHERE lot_number='FL-2026-QA' 
     LIMIT 1;" 2>/dev/null)

# Check if result found, parse it
RECORD_FOUND="false"
LOT=""
EXP=""
QTY=""
CVX=""
MFG=""

if [ -n "$DB_RESULT" ]; then
    RECORD_FOUND="true"
    # Parse tab-separated output
    LOT=$(echo "$DB_RESULT" | awk '{print $1}')
    EXP=$(echo "$DB_RESULT" | awk '{print $2}')
    QTY=$(echo "$DB_RESULT" | awk '{print $3}')
    CVX=$(echo "$DB_RESULT" | awk '{print $4}')
    MFG=$(echo "$DB_RESULT" | awk '{print $5}')
fi

# 4. Check application state (Firefox running)
APP_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create JSON result file
#    Using a temp file to avoid permission issues, then moving
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "record_found": $RECORD_FOUND,
    "data": {
        "lot_number": "$LOT",
        "expiration_date": "$EXP",
        "quantity": "$QTY",
        "cvx_code": "$CVX",
        "manufacturer": "$MFG"
    },
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissive permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="