#!/bin/bash
set -e
echo "=== Setting up update_service_price task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure HospitalRun is accessible
echo "Checking HospitalRun availability..."
wait_for_hospitalrun_ready 60

# 2. Prepare the specific pricing item in CouchDB
# We use a fixed ID so we can verify if it was updated vs deleted/recreated
DOC_ID="pricing_task_target_001"
INITIAL_NAME="General Consultation"
INITIAL_PRICE=50.00

echo "Seeding pricing item: $INITIAL_NAME ($INITIAL_PRICE)..."

# Delete if exists to ensure clean state
hr_couch_delete "$DOC_ID" 2>/dev/null || true

# Create the pricing item
# HospitalRun pricing items have structure: { _id, data: { type: 'pricing', name: ..., price: ... } }
SEED_JSON=$(cat <<EOF
{
  "data": {
    "type": "pricing",
    "name": "$INITIAL_NAME",
    "price": $INITIAL_PRICE,
    "pricingType": "Service",
    "percentage": 0,
    "description": "Standard basic consultation fee"
  }
}
EOF
)

hr_couch_put "$DOC_ID" "$SEED_JSON"
echo "Pricing item seeded with ID: $DOC_ID"

# Record initial revision for comparison
INITIAL_REV=$(hr_couch_get "$DOC_ID" | python3 -c "import sys,json; print(json.load(sys.stdin).get('_rev',''))")
echo "$INITIAL_REV" > /tmp/initial_doc_rev.txt
echo "Initial revision: $INITIAL_REV"

# 3. Ensure Firefox is open and logged in
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# 4. Fix PouchDB sync issues (loading spinner fix)
fix_offline_sync

# 5. Navigate to the Pricing section to save time (or Main Dashboard)
# Navigation to Pricing directly: http://localhost:3000/#/pricing
echo "Navigating to Pricing module..."
navigate_firefox_to "http://localhost:3000/#/pricing"

# Wait for the list to render
sleep 5

# 6. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="