#!/bin/bash
echo "=== Setting up equipment_room_short_term_loans task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------
# 1. Ensure required Users exist (using MariaDB direct insert for robustness)
# ---------------------------------------------------------------
echo "  Injecting users..."
snipeit_db_query "INSERT IGNORE INTO users (first_name, last_name, username, email, activated, created_at, updated_at) VALUES 
('Emily', 'Chen', 'echen', 'echen@university.edu', 1, NOW(), NOW()), 
('Marcus', 'Johnson', 'mjohnson', 'mjohnson@university.edu', 1, NOW(), NOW()), 
('Sarah', 'Smith', 'ssmith', 'ssmith@university.edu', 1, NOW(), NOW()), 
('David', 'Kim', 'dkim', 'dkim@university.edu', 1, NOW(), NOW());"

# ---------------------------------------------------------------
# 2. Setup Models and Statuses
# ---------------------------------------------------------------
# Get a baseline model ID to use for the assets
MDL_LAPTOP=$(snipeit_db_query "SELECT id FROM models LIMIT 1" | tr -d '[:space:]')
if [ -z "$MDL_LAPTOP" ]; then
    echo "Creating generic model..."
    snipeit_api POST "models" '{"name":"Generic IT Equipment","category_id":1,"manufacturer_id":1}'
    MDL_LAPTOP=$(snipeit_db_query "SELECT id FROM models LIMIT 1" | tr -d '[:space:]')
fi

SL_READY=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')

# ---------------------------------------------------------------
# 3. Create Required Assets
# ---------------------------------------------------------------
echo "  Injecting assets..."

# Clear if they exist from a previous run
for tag in "LIB-MAC-001" "LIB-MAC-002" "LIB-CAM-001" "LIB-IPAD-001"; do
    if asset_exists_by_tag "$tag"; then
        snipeit_db_query "DELETE FROM assets WHERE asset_tag='$tag'"
    fi
done

# Create assets via API
snipeit_api POST "hardware" "{\"asset_tag\":\"LIB-MAC-001\",\"name\":\"MacBook Pro\",\"model_id\":$MDL_LAPTOP,\"status_id\":$SL_READY,\"notes\":\"Media arts editing laptop\"}"
snipeit_api POST "hardware" "{\"asset_tag\":\"LIB-MAC-002\",\"name\":\"MacBook Pro\",\"model_id\":$MDL_LAPTOP,\"status_id\":$SL_READY,\"notes\":\"Media arts editing laptop\"}"
snipeit_api POST "hardware" "{\"asset_tag\":\"LIB-CAM-001\",\"name\":\"Canon EOS 80D\",\"model_id\":$MDL_LAPTOP,\"status_id\":$SL_READY,\"notes\":\"Photography class camera\"}"
snipeit_api POST "hardware" "{\"asset_tag\":\"LIB-IPAD-001\",\"name\":\"iPad Pro\",\"model_id\":$MDL_LAPTOP,\"status_id\":$SL_READY,\"notes\":\"Drawing tablet\"}"

sleep 2

# ---------------------------------------------------------------
# 4. Check out the iPad to David Kim
# ---------------------------------------------------------------
echo "  Checking out iPad to David Kim..."
IPAD_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='LIB-IPAD-001' LIMIT 1" | tr -d '[:space:]')
DKIM_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='dkim' LIMIT 1" | tr -d '[:space:]')

snipeit_api POST "hardware/${IPAD_ID}/checkout" "{\"assigned_user\":$DKIM_ID,\"checkout_to_type\":\"user\",\"note\":\"Semester long loan\"}"
sleep 2

# ---------------------------------------------------------------
# 5. Launch UI
# ---------------------------------------------------------------
# Ensure Firefox is running and on Snipe-IT
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000"
sleep 3
take_screenshot /tmp/equipment_room_initial.png

echo "=== equipment_room_short_term_loans task setup complete ==="