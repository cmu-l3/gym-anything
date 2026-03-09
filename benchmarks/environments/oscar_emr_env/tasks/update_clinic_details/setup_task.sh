#!/bin/bash
# Setup script for Update Clinic Details task
# Resets the facility record to a known "old" state

echo "=== Setting up Update Clinic Details Task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Oscar DB is ready
wait_for_oscar_http 60

# 2. Reset the Facility Record
# We want to ensure there is a main facility (usually ID 1) with "old" data
# Oscar's facility table usually has columns: id, name, address, city, province, postal, phone, fax, email...

echo "Resetting facility record..."

# Check if ID 1 exists
ID_EXISTS=$(oscar_query "SELECT count(*) FROM facility WHERE id=1" || echo "0")

if [ "$ID_EXISTS" -eq "0" ]; then
    # Insert if missing
    echo "Inserting default facility..."
    oscar_query "INSERT INTO facility (id, name, address, city, province, postal, phone, fax, email) VALUES (1, 'OSCAR Demo', '123 Old Street', 'Hamilton', 'ON', 'L8P 1A1', '905-555-0000', '905-555-0001', 'admin@oscardemo.ca');"
else
    # Update to old values
    echo "Updating existing facility to old values..."
    oscar_query "UPDATE facility SET address='123 Old Street', city='Hamilton', postal='L8P 1A1', phone='905-555-0000', fax='905-555-0001' WHERE id=1;"
fi

# 3. Record initial state for verification
INITIAL_STATE=$(oscar_query "SELECT id, address, phone, fax FROM facility WHERE id=1")
echo "Initial State: $INITIAL_STATE"
echo "$INITIAL_STATE" > /tmp/initial_facility_state.txt

# Record total count to detect if agent creates a NEW one instead of updating
INITIAL_COUNT=$(oscar_query "SELECT count(*) FROM facility")
echo "$INITIAL_COUNT" > /tmp/initial_facility_count.txt

# 4. Record timestamp
date +%s > /tmp/task_start_time.txt

# 5. Launch Firefox
ensure_firefox_on_oscar

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Task: Update Facility ID 1 to:"
echo "  Address: 455 Dovercourt Rd, Suite 102"
echo "  Phone:   416-555-0198"
echo "  Fax:     416-555-0199"