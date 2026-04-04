#!/bin/bash
echo "=== Setting up identify_low_stock_items task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Remove any existing report file
rm -f /home/ga/low_stock_report.txt

# Verify HospitalRun is available
echo "Checking HospitalRun availability..."
for i in $(seq 1 15); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo "HospitalRun is available"
        break
    fi
    sleep 5
done

# Clear existing inventory items to ensure clean state
echo "Clearing existing inventory..."
# Fetch all docs, filter for type 'inventory', delete them
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" 2>/dev/null | \
python3 -c "
import sys, json
data = json.load(sys.stdin)
for row in data.get('rows', []):
    doc = row.get('doc', {})
    d = doc.get('data', doc) # HospitalRun sometimes wraps data
    if d.get('type') == 'inventory' or doc.get('type') == 'inventory':
        print(row['id'] + '|' + doc.get('_rev',''))
" | while IFS='|' read -r doc_id rev; do
    if [ -n "$doc_id" ]; then
        curl -s -X DELETE "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${doc_id}?rev=${rev}" > /dev/null
    fi
done

# Seed Inventory Data
echo "Seeding inventory items..."

# Function to add item
add_item() {
    local id="$1"
    local name="$2"
    local qty="$3"
    # Create valid CouchDB doc structure for HospitalRun
    # HospitalRun expects: _id, data: { ...fields... }
    # Fields: name, quantity, type='inventory', status='Active', etc.
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${id}" \
        -H "Content-Type: application/json" \
        -d "{
          \"data\": {
            \"friendlyId\": \"${id#inv_}\",
            \"name\": \"${name}\",
            \"quantity\": ${qty},
            \"type\": \"inventory\",
            \"status\": \"Active\",
            \"crossReference\": \"\",
            \"distributionUnit\": \"Box\",
            \"price\": 10.00
          }
        }" > /dev/null
}

# Low Stock Items (< 20)
add_item "inv_001" "Amoxicillin 500mg" 12
add_item "inv_002" "Sterile Gauze Pads" 5
add_item "inv_003" "Disposable Syringes 10ml" 18

# High Stock Items (>= 20)
add_item "inv_004" "Surgical Gloves (Size M)" 150
add_item "inv_005" "Saline Solution 1L" 45
add_item "inv_006" "N95 Respirator Masks" 200

echo "Inventory seeded."

# Ensure Firefox is open and logged in
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# Wait for DB sync
wait_for_db_ready

# Navigate to Dashboard to start (Agent must find Inventory)
navigate_firefox_to "http://localhost:3000/"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="