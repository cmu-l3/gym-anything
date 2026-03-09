#!/bin/bash
# Setup script for Update Vaccine Inventory task

echo "=== Setting up Update Vaccine Inventory Task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure the Vaccine Type 'Adacel' exists
echo "Ensuring Adacel prevention type exists..."
# Check if exists
TYPE_EXISTS=$(oscar_query "SELECT COUNT(*) FROM prevention_type WHERE prevention_type='Adacel'" || echo "0")

if [ "$TYPE_EXISTS" -eq "0" ]; then
    oscar_query "INSERT INTO prevention_type (prevention_type, prevention_name, val, deleted) VALUES ('Adacel', 'Adacel (Tdap)', '0', 0);"
fi

# Get the ID for foreign key
TYPE_ID=$(oscar_query "SELECT id FROM prevention_type WHERE prevention_type='Adacel' LIMIT 1")
echo "Adacel Type ID: $TYPE_ID"

if [ -z "$TYPE_ID" ]; then
    echo "ERROR: Could not retrieve Adacel type ID"
    exit 1
fi

# 2. Reset the specific Lot 'ADC-AUDIT-25' to known initial state (25 units)
echo "Resetting Lot ADC-AUDIT-25..."
# Delete existing to prevent duplicates
oscar_query "DELETE FROM prevention_lot WHERE lot_number='ADC-AUDIT-25';"

# Insert fresh record with initial quantity 25
# active=1 means available
oscar_query "INSERT INTO prevention_lot (procedureId, lot_number, expiry_date, unit, active) VALUES ('$TYPE_ID', 'ADC-AUDIT-25', '2027-12-31', 25, 1);"

# 3. Record initial state for verification
INITIAL_UNIT=$(oscar_query "SELECT unit FROM prevention_lot WHERE lot_number='ADC-AUDIT-25' LIMIT 1")
echo "$INITIAL_UNIT" > /tmp/initial_inventory_unit.txt
echo "Initial inventory unit recorded: $INITIAL_UNIT"

# Record task start timestamp
date +%s > /tmp/task_start_time.txt

# 4. Prepare Browser
ensure_firefox_on_oscar

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Target Lot: ADC-AUDIT-25"
echo "Initial Qty: 25"
echo "Target Qty: 12"