#!/bin/bash
# Export script for Add Immunization Lot Task

echo "=== Exporting Add Immunization Lot Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot first
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Get timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Expected values
EXPECTED_LOT="FL2024-8847"
EXPECTED_NDC="49281-0421-50"

# Get initial counts
INITIAL_DRUG_COUNT=$(cat /tmp/initial_drug_count.txt 2>/dev/null || echo "0")
INITIAL_INVENTORY_COUNT=$(cat /tmp/initial_inventory_count.txt 2>/dev/null || echo "0")

# Get current counts
CURRENT_DRUG_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM drugs" 2>/dev/null || echo "0")
CURRENT_INVENTORY_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM drug_inventory" 2>/dev/null || echo "0")

echo "Drug count: initial=$INITIAL_DRUG_COUNT, current=$CURRENT_DRUG_COUNT"
echo "Inventory count: initial=$INITIAL_INVENTORY_COUNT, current=$CURRENT_INVENTORY_COUNT"

# Query for the expected lot in drug_inventory table
echo ""
echo "=== Searching for lot '$EXPECTED_LOT' in drug_inventory ==="
LOT_RECORD=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT inventory_id, drug_id, lot_number, expiration, manufacturer, on_hand 
     FROM drug_inventory 
     WHERE lot_number='$EXPECTED_LOT' 
     ORDER BY inventory_id DESC LIMIT 1" 2>/dev/null)

if [ -n "$LOT_RECORD" ]; then
    echo "Found lot record in drug_inventory:"
    echo "$LOT_RECORD"
fi

# Also check drugs table for NDC code
echo ""
echo "=== Searching for NDC '$EXPECTED_NDC' in drugs table ==="
DRUG_RECORD=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT drug_id, name, ndc_number, form, active 
     FROM drugs 
     WHERE ndc_number='$EXPECTED_NDC' OR name LIKE '%Influenza%' OR name LIKE '%$EXPECTED_LOT%'
     ORDER BY drug_id DESC LIMIT 5" 2>/dev/null)

if [ -n "$DRUG_RECORD" ]; then
    echo "Found matching drug records:"
    echo "$DRUG_RECORD"
fi

# Parse lot record if found
LOT_FOUND="false"
LOT_INVENTORY_ID=""
LOT_DRUG_ID=""
LOT_NUMBER=""
LOT_EXPIRATION=""
LOT_MANUFACTURER=""
LOT_QUANTITY=""

if [ -n "$LOT_RECORD" ]; then
    LOT_FOUND="true"
    LOT_INVENTORY_ID=$(echo "$LOT_RECORD" | cut -f1)
    LOT_DRUG_ID=$(echo "$LOT_RECORD" | cut -f2)
    LOT_NUMBER=$(echo "$LOT_RECORD" | cut -f3)
    LOT_EXPIRATION=$(echo "$LOT_RECORD" | cut -f4)
    LOT_MANUFACTURER=$(echo "$LOT_RECORD" | cut -f5)
    LOT_QUANTITY=$(echo "$LOT_RECORD" | cut -f6)
    
    echo ""
    echo "Parsed lot record:"
    echo "  Inventory ID: $LOT_INVENTORY_ID"
    echo "  Drug ID: $LOT_DRUG_ID"
    echo "  Lot Number: $LOT_NUMBER"
    echo "  Expiration: $LOT_EXPIRATION"
    echo "  Manufacturer: $LOT_MANUFACTURER"
    echo "  Quantity: $LOT_QUANTITY"
fi

# If not found in drug_inventory, check if drug was added to drugs table
DRUG_FOUND="false"
DRUG_ID=""
DRUG_NAME=""
DRUG_NDC=""

if [ -n "$DRUG_RECORD" ]; then
    # Parse first matching drug record
    FIRST_DRUG=$(echo "$DRUG_RECORD" | head -1)
    if [ -n "$FIRST_DRUG" ]; then
        DRUG_FOUND="true"
        DRUG_ID=$(echo "$FIRST_DRUG" | cut -f1)
        DRUG_NAME=$(echo "$FIRST_DRUG" | cut -f2)
        DRUG_NDC=$(echo "$FIRST_DRUG" | cut -f3)
        
        echo ""
        echo "Parsed drug record:"
        echo "  Drug ID: $DRUG_ID"
        echo "  Name: $DRUG_NAME"
        echo "  NDC: $DRUG_NDC"
    fi
fi

# Check for any new inventory records added during task
echo ""
echo "=== Checking for any new inventory records ==="
NEW_INVENTORY=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT inventory_id, drug_id, lot_number, expiration, manufacturer, on_hand 
     FROM drug_inventory 
     WHERE inventory_id > $INITIAL_INVENTORY_COUNT
     ORDER BY inventory_id DESC LIMIT 5" 2>/dev/null)

if [ -n "$NEW_INVENTORY" ]; then
    echo "New inventory records found:"
    echo "$NEW_INVENTORY"
fi

# Check for any new drugs added during task
echo ""
echo "=== Checking for any new drug records ==="
NEW_DRUGS=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT drug_id, name, ndc_number, form 
     FROM drugs 
     WHERE drug_id > $INITIAL_DRUG_COUNT
     ORDER BY drug_id DESC LIMIT 5" 2>/dev/null)

if [ -n "$NEW_DRUGS" ]; then
    echo "New drug records found:"
    echo "$NEW_DRUGS"
fi

# Determine if records were created during task
NEW_DRUG_ADDED="false"
NEW_INVENTORY_ADDED="false"

if [ "$CURRENT_DRUG_COUNT" -gt "$INITIAL_DRUG_COUNT" ]; then
    NEW_DRUG_ADDED="true"
fi

if [ "$CURRENT_INVENTORY_COUNT" -gt "$INITIAL_INVENTORY_COUNT" ]; then
    NEW_INVENTORY_ADDED="true"
fi

# Escape special characters for JSON
LOT_MANUFACTURER_ESCAPED=$(echo "$LOT_MANUFACTURER" | sed 's/"/\\"/g' | tr '\n' ' ')
DRUG_NAME_ESCAPED=$(echo "$DRUG_NAME" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/immunization_lot_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "initial_drug_count": ${INITIAL_DRUG_COUNT:-0},
    "current_drug_count": ${CURRENT_DRUG_COUNT:-0},
    "initial_inventory_count": ${INITIAL_INVENTORY_COUNT:-0},
    "current_inventory_count": ${CURRENT_INVENTORY_COUNT:-0},
    "new_drug_added": $NEW_DRUG_ADDED,
    "new_inventory_added": $NEW_INVENTORY_ADDED,
    "lot_record_found": $LOT_FOUND,
    "lot_record": {
        "inventory_id": "$LOT_INVENTORY_ID",
        "drug_id": "$LOT_DRUG_ID",
        "lot_number": "$LOT_NUMBER",
        "expiration": "$LOT_EXPIRATION",
        "manufacturer": "$LOT_MANUFACTURER_ESCAPED",
        "quantity": "$LOT_QUANTITY"
    },
    "drug_record_found": $DRUG_FOUND,
    "drug_record": {
        "drug_id": "$DRUG_ID",
        "name": "$DRUG_NAME_ESCAPED",
        "ndc": "$DRUG_NDC"
    },
    "expected": {
        "lot_number": "$EXPECTED_LOT",
        "ndc": "$EXPECTED_NDC",
        "manufacturer": "Sanofi Pasteur",
        "expiration": "2025-06-30",
        "quantity": 50
    },
    "screenshot_final": "/tmp/task_final.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result JSON
rm -f /tmp/immunization_lot_result.json 2>/dev/null || sudo rm -f /tmp/immunization_lot_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/immunization_lot_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/immunization_lot_result.json
chmod 666 /tmp/immunization_lot_result.json 2>/dev/null || sudo chmod 666 /tmp/immunization_lot_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/immunization_lot_result.json"
cat /tmp/immunization_lot_result.json

echo ""
echo "=== Export Complete ==="