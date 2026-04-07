#!/bin/bash
set -e
echo "=== Setting up new_hire_accessory_provisioning task ==="

# Source Snipe-IT utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time and initial accessory count (Anti-gaming)
date +%s > /tmp/task_start_time.txt

INITIAL_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM accessories WHERE deleted_at IS NULL" 2>/dev/null | tr -d '[:space:]' || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_accessory_count.txt
echo "Initial accessory count: $INITIAL_COUNT"

# 2. Ensure "Computer Peripherals" category exists
echo "Setting up accessory category..."
snipeit_api POST "categories" '{"name":"Computer Peripherals","category_type":"accessory"}' >/dev/null 2>&1 || true

# 3. Ensure manufacturers exist (they might already exist from seed data, but ensure they do)
echo "Ensuring manufacturers exist..."
for mfr in "Dell" "HP" "Lenovo" "Poly"; do
    snipeit_api POST "manufacturers" "{\"name\":\"$mfr\"}" >/dev/null 2>&1 || true
done

# 4. Get a valid location ID to assign to the users
LOC_ID=$(snipeit_api GET "locations?limit=1" | jq -r '.rows[0].id // 1' 2>/dev/null || echo "1")

# 5. Create the 3 faculty users
echo "Creating faculty users..."
snipeit_api POST "users" "{\"first_name\":\"Maria\",\"last_name\":\"Santos\",\"username\":\"msantos\",\"password\":\"Faculty2025!\",\"password_confirmation\":\"Faculty2025!\",\"email\":\"msantos@university.edu\",\"location_id\":$LOC_ID}" >/dev/null 2>&1 || true
snipeit_api POST "users" "{\"first_name\":\"James\",\"last_name\":\"Liu\",\"username\":\"jliu\",\"password\":\"Faculty2025!\",\"password_confirmation\":\"Faculty2025!\",\"email\":\"jliu@university.edu\",\"location_id\":$LOC_ID}" >/dev/null 2>&1 || true
snipeit_api POST "users" "{\"first_name\":\"Aisha\",\"last_name\":\"Patel\",\"username\":\"apatel\",\"password\":\"Faculty2025!\",\"password_confirmation\":\"Faculty2025!\",\"email\":\"apatel@university.edu\",\"location_id\":$LOC_ID}" >/dev/null 2>&1 || true

# 6. Ensure Snipe-IT is running in Firefox
echo "Starting browser..."
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000"
sleep 3

# Take an initial screenshot to show task starting state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="