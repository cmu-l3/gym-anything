#!/bin/bash
# Export script for Add Vaccine Lot task
# Verifies the existence of the specific vaccine lot in the database

echo "=== Exporting Add Vaccine Lot Result ==="

source /workspace/scripts/task_utils.sh

# Target data
TARGET_LOT="FL2025-X9"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Query the database for the specific lot
# We check 'prevention_lot' which is the standard table for vaccine inventory in OSCAR
# Columns usually include: id, prevention_type_id, lot_number, expiry_date
echo "Querying database for lot $TARGET_LOT..."

# Get the record if it exists
# We fetch Lot Number and Expiry Date
LOT_RECORD=$(oscar_query "SELECT lot_number, expiry_date, prevention_type_id FROM prevention_lot WHERE lot_number='$TARGET_LOT' LIMIT 1" 2>/dev/null)

if [ -z "$LOT_RECORD" ]; then
    # Fallback: check immunization_lot table if prevention_lot is empty/missing
    LOT_RECORD=$(oscar_query "SELECT lot_number, expiry_date, item_id FROM immunization_lot WHERE lot_number='$TARGET_LOT' LIMIT 1" 2>/dev/null)
fi

FOUND="false"
FOUND_LOT=""
FOUND_EXPIRY=""
FOUND_TYPE_ID=""

if [ -n "$LOT_RECORD" ]; then
    FOUND="true"
    FOUND_LOT=$(echo "$LOT_RECORD" | cut -f1)
    FOUND_EXPIRY=$(echo "$LOT_RECORD" | cut -f2)
    FOUND_TYPE_ID=$(echo "$LOT_RECORD" | cut -f3)
fi

# 3. Get total count to check for "do nothing" (though specific query covers this mostly)
FINAL_COUNT=$(oscar_query "SELECT COUNT(*) FROM prevention_lot" 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_lot_count.txt 2>/dev/null || echo "0")

# 4. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "lot_found": $FOUND,
    "found_lot_number": "$FOUND_LOT",
    "found_expiry_date": "$FOUND_EXPIRY",
    "prevention_type_id": "$FOUND_TYPE_ID",
    "initial_count": $INITIAL_COUNT,
    "final_count": $FINAL_COUNT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="