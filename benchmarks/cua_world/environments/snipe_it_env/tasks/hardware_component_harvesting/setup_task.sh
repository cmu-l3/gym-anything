#!/bin/bash
echo "=== Setting up hardware_component_harvesting task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up any previous runs
snipeit_db_query "DELETE FROM locations WHERE name IN ('Hardware Triage', 'Boston HQ')"
snipeit_db_query "DELETE FROM status_labels WHERE name='Pending E-Waste'"
snipeit_db_query "DELETE FROM assets WHERE asset_tag LIKE 'TRG-%'"
snipeit_db_query "DELETE FROM components WHERE name IN ('16GB RAM DDR4', '1TB NVMe SSD')"
snipeit_db_query "DELETE FROM categories WHERE name='Harvested Parts'"

# 2. Create Target Locations
snipeit_db_query "INSERT INTO locations (name, created_at, updated_at) VALUES ('Hardware Triage', NOW(), NOW())"
LOC_TRIAGE=$(snipeit_db_query "SELECT id FROM locations WHERE name='Hardware Triage' ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')

snipeit_db_query "INSERT INTO locations (name, created_at, updated_at) VALUES ('Boston HQ', NOW(), NOW())"
LOC_BOSTON=$(snipeit_db_query "SELECT id FROM locations WHERE name='Boston HQ' ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')

# 3. Create Component Category and Components
snipeit_db_query "INSERT INTO categories (name, category_type, created_at, updated_at) VALUES ('Harvested Parts', 'component', NOW(), NOW())"
CAT_COMP=$(snipeit_db_query "SELECT id FROM categories WHERE name='Harvested Parts' AND category_type='component' LIMIT 1" | tr -d '[:space:]')

snipeit_db_query "INSERT INTO components (name, category_id, qty, num_remaining, location_id, created_at, updated_at) VALUES ('16GB RAM DDR4', $CAT_COMP, 10, 10, $LOC_TRIAGE, NOW(), NOW())"
COMP_RAM=$(snipeit_db_query "SELECT id FROM components WHERE name='16GB RAM DDR4' ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')

snipeit_db_query "INSERT INTO components (name, category_id, qty, num_remaining, location_id, created_at, updated_at) VALUES ('1TB NVMe SSD', $CAT_COMP, 10, 10, $LOC_TRIAGE, NOW(), NOW())"
COMP_SSD=$(snipeit_db_query "SELECT id FROM components WHERE name='1TB NVMe SSD' ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')

# 4. Get required IDs for Assets
SL_REPAIR=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Out for Repair' LIMIT 1" | tr -d '[:space:]')
SL_READY=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')
MDL_ID=$(snipeit_db_query "SELECT id FROM models WHERE name LIKE '%ThinkPad T14%' LIMIT 1" | tr -d '[:space:]')
if [ -z "$MDL_ID" ]; then MDL_ID=$(snipeit_db_query "SELECT id FROM models LIMIT 1" | tr -d '[:space:]'); fi

# 5. Create Assets and Checkout Components
echo "Injecting assets and checking out components..."
for i in {1..5}; do
    STATUS=$SL_REPAIR
    if [ $i -ge 4 ]; then STATUS=$SL_READY; fi
    
    # Create asset
    snipeit_api POST "hardware" "{\"asset_tag\":\"TRG-00$i\",\"name\":\"Triage Laptop 00$i\",\"model_id\":$MDL_ID,\"status_id\":$STATUS,\"rtd_location_id\":$LOC_TRIAGE}"
    sleep 1
    
    ASSET_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='TRG-00$i' ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')
    
    # Check out 1 RAM directly via DB (to perfectly mimic a real checkout)
    snipeit_db_query "INSERT INTO components_assets (component_id, asset_id, assigned_qty, created_at, updated_at) VALUES ($COMP_RAM, $ASSET_ID, 1, NOW(), NOW())"
    snipeit_db_query "UPDATE components SET num_remaining = num_remaining - 1 WHERE id=$COMP_RAM"
    
    # Check out 1 SSD
    snipeit_db_query "INSERT INTO components_assets (component_id, asset_id, assigned_qty, created_at, updated_at) VALUES ($COMP_SSD, $ASSET_ID, 1, NOW(), NOW())"
    snipeit_db_query "UPDATE components SET num_remaining = num_remaining - 1 WHERE id=$COMP_SSD"
done

# 6. Record baseline timestamp
date +%s > /tmp/task_start_time.txt

# 7. Start Firefox
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000"
sleep 3
take_screenshot /tmp/hardware_component_harvesting_initial.png

echo "=== Setup complete ==="