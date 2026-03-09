#!/bin/bash
# Export script for Update Vaccine Inventory task

echo "=== Exporting Update Vaccine Inventory Result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the final state of the lot
echo "Querying database for Lot ADC-AUDIT-25..."

# We select unit, active status, and procedureId to ensure it wasn't deleted or unlinked
# prevention_lot table columns: id, procedureId, lot_number, expiry_date, unit, active...
LOT_DATA=$(oscar_query "SELECT unit, active, procedureId FROM prevention_lot WHERE lot_number='ADC-AUDIT-25' LIMIT 1")

# Parse result (tab separated)
FINAL_UNIT=""
FINAL_ACTIVE=""
PROC_ID=""
LOT_EXISTS="false"

if [ -n "$LOT_DATA" ]; then
    LOT_EXISTS="true"
    FINAL_UNIT=$(echo "$LOT_DATA" | cut -f1)
    FINAL_ACTIVE=$(echo "$LOT_DATA" | cut -f2)
    PROC_ID=$(echo "$LOT_DATA" | cut -f3)
fi

INITIAL_UNIT=$(cat /tmp/initial_inventory_unit.txt 2>/dev/null || echo "25")

echo "Final State: Exists=$LOT_EXISTS, Unit=$FINAL_UNIT, Active=$FINAL_ACTIVE"

# Create JSON result
TEMP_JSON=$(mktemp /tmp/inventory_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "lot_exists": $LOT_EXISTS,
    "initial_unit": $INITIAL_UNIT,
    "final_unit": ${FINAL_UNIT:-"null"},
    "active": ${FINAL_ACTIVE:-"null"},
    "procedure_id": "${PROC_ID:-""}",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move to /tmp/task_result.json
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved."
cat /tmp/task_result.json
echo "=== Export Complete ==="