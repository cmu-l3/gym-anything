#!/bin/bash
echo "=== Setting up leased_equipment_return task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------
# 1. Create Required Suppliers
# ---------------------------------------------------------------
echo "  Creating suppliers..."
snipeit_db_query "INSERT INTO suppliers (name, created_at, updated_at) VALUES ('Apple Financial Services', NOW(), NOW());"
SUP_APPLE=$(snipeit_db_query "SELECT id FROM suppliers WHERE name='Apple Financial Services' LIMIT 1" | tr -d '[:space:]')

snipeit_db_query "INSERT INTO suppliers (name, created_at, updated_at) VALUES ('CDW', NOW(), NOW());"
SUP_CDW=$(snipeit_db_query "SELECT id FROM suppliers WHERE name='CDW' LIMIT 1" | tr -d '[:space:]')

# ---------------------------------------------------------------
# 2. Get Necessary References (Model, Status, User)
# ---------------------------------------------------------------
echo "  Fetching reference IDs..."
# Try to get a laptop category, fallback to 1
CAT_LAPTOP=$(snipeit_db_query "SELECT id FROM categories WHERE name LIKE '%Laptop%' LIMIT 1" | tr -d '[:space:]')
if [ -z "$CAT_LAPTOP" ]; then CAT_LAPTOP=1; fi

# Create Apple Manufacturer if needed
MAN_APPLE=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name LIKE '%Apple%' LIMIT 1" | tr -d '[:space:]')
if [ -z "$MAN_APPLE" ]; then
    snipeit_db_query "INSERT INTO manufacturers (name, created_at, updated_at) VALUES ('Apple', NOW(), NOW());"
    MAN_APPLE=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Apple' LIMIT 1" | tr -d '[:space:]')
fi

# Create MacBook Pro 16 model
snipeit_db_query "INSERT INTO models (name, model_number, category_id, manufacturer_id, created_at, updated_at) VALUES ('MacBook Pro 16', 'MBP16', $CAT_LAPTOP, $MAN_APPLE, NOW(), NOW());"
MDL_MBP=$(snipeit_db_query "SELECT id FROM models WHERE name='MacBook Pro 16' LIMIT 1" | tr -d '[:space:]')

# Get Deployed Status ID
SL_DEPLOYED=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Deployed' LIMIT 1" | tr -d '[:space:]')

# Get a target user ID
USER_ID=$(snipeit_db_query "SELECT id FROM users WHERE deleted_at IS NULL AND username != 'admin' LIMIT 1" | tr -d '[:space:]')
if [ -z "$USER_ID" ]; then USER_ID=1; fi

# ---------------------------------------------------------------
# 3. Create Leased Assets (Apple Financial Services)
# ---------------------------------------------------------------
echo "  Injecting leased assets..."
for i in {1..4}; do
    TAG="LEASE-00$i"
    # Ensure tag doesn't already exist
    snipeit_db_query "DELETE FROM assets WHERE asset_tag='$TAG';"
    # Insert as Deployed to user
    snipeit_db_query "INSERT INTO assets (asset_tag, name, model_id, status_id, supplier_id, assigned_to, assigned_type, purchase_date, purchase_cost, created_at, updated_at) VALUES ('$TAG', 'MacBook Pro 16 - Engineering', $MDL_MBP, $SL_DEPLOYED, $SUP_APPLE, $USER_ID, 'App\\\\Models\\\\User', '2022-03-01', 2800.00, NOW(), NOW());"
done

# ---------------------------------------------------------------
# 4. Create Owned Assets (CDW)
# ---------------------------------------------------------------
echo "  Injecting owned assets..."
for i in {1..3}; do
    TAG="OWNED-00$i"
    snipeit_db_query "DELETE FROM assets WHERE asset_tag='$TAG';"
    # Insert as Deployed to user
    snipeit_db_query "INSERT INTO assets (asset_tag, name, model_id, status_id, supplier_id, assigned_to, assigned_type, purchase_date, purchase_cost, created_at, updated_at) VALUES ('$TAG', 'MacBook Pro 16 - Management', $MDL_MBP, $SL_DEPLOYED, $SUP_CDW, $USER_ID, 'App\\\\Models\\\\User', '2023-08-15', 2650.00, NOW(), NOW());"
done

# ---------------------------------------------------------------
# 5. Ensure UI Accessibility
# ---------------------------------------------------------------
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000/hardware"
sleep 3
take_screenshot /tmp/task_initial.png

echo "=== leased_equipment_return task setup complete ==="