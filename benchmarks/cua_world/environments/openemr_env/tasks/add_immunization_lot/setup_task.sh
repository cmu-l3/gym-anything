#!/bin/bash
# Setup script for Add Immunization Lot Task

echo "=== Setting up Add Immunization Lot Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Expected lot number (should NOT exist before task)
EXPECTED_LOT="FL2024-8847"

# Clean up any pre-existing test data (ensure clean slate)
echo "Ensuring clean slate - removing any pre-existing test lot records..."

# Check drugs table for existing records
EXISTING_DRUG=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT drug_id FROM drugs WHERE ndc_number='49281-0421-50' OR name LIKE '%FL2024-8847%' LIMIT 1" 2>/dev/null || echo "")

if [ -n "$EXISTING_DRUG" ]; then
    echo "Found existing drug record (drug_id=$EXISTING_DRUG), removing for clean test..."
    docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
        "DELETE FROM drug_inventory WHERE drug_id='$EXISTING_DRUG'" 2>/dev/null || true
    docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
        "DELETE FROM drugs WHERE drug_id='$EXISTING_DRUG'" 2>/dev/null || true
fi

# Also check drug_inventory for lot number directly
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
    "DELETE FROM drug_inventory WHERE lot_number='$EXPECTED_LOT'" 2>/dev/null || true

# Record initial counts for verification
echo "Recording initial inventory counts..."

INITIAL_DRUG_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM drugs" 2>/dev/null || echo "0")
echo "$INITIAL_DRUG_COUNT" > /tmp/initial_drug_count.txt
echo "Initial drug count: $INITIAL_DRUG_COUNT"

INITIAL_INVENTORY_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM drug_inventory" 2>/dev/null || echo "0")
echo "$INITIAL_INVENTORY_COUNT" > /tmp/initial_inventory_count.txt
echo "Initial inventory count: $INITIAL_INVENTORY_COUNT"

# Verify test lot doesn't exist
LOT_EXISTS=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM drug_inventory WHERE lot_number='$EXPECTED_LOT'" 2>/dev/null || echo "0")
if [ "$LOT_EXISTS" -gt "0" ]; then
    echo "WARNING: Test lot still exists after cleanup attempt!"
else
    echo "Confirmed: Test lot '$EXPECTED_LOT' does not exist (clean slate)"
fi

# Ensure Firefox is running on OpenEMR
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|OpenEMR" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot for audit trail
echo "Capturing initial screenshot..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Add Immunization Lot Task Setup Complete ==="
echo ""
echo "Task: Add a new vaccine lot record to OpenEMR inventory"
echo ""
echo "Required Details:"
echo "  - Vaccine: Influenza (seasonal, injectable)"
echo "  - NDC Code: 49281-0421-50"
echo "  - Lot Number: FL2024-8847"
echo "  - Manufacturer: Sanofi Pasteur"
echo "  - Expiration: 2025-06-30"
echo "  - Quantity: 50 doses"
echo ""
echo "Login: admin / pass"
echo ""
echo "Navigate to Inventory > Drugs or Administration > Products"
echo "to find the drug/immunization inventory management area."
echo ""