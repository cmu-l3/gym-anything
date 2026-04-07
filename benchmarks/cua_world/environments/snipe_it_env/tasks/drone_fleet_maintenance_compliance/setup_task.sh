#!/bin/bash
set -e
echo "=== Setting up drone_fleet_maintenance_compliance task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------
# Clean state (in case of re-runs) to prevent foreign key errors
# ---------------------------------------------------------------
snipeit_db_query "DELETE FROM assets WHERE asset_tag LIKE 'DRONE-%'"
snipeit_db_query "DELETE FROM models WHERE name='DJI Mavic 3 Enterprise'"
snipeit_db_query "DELETE FROM categories WHERE name='Drones'"
snipeit_db_query "DELETE FROM manufacturers WHERE name='DJI'"
snipeit_db_query "DELETE FROM suppliers WHERE name='DJI Enterprise Support'"
snipeit_db_query "DELETE FROM suppliers WHERE name='Federal Aviation Administration'"
snipeit_db_query "DELETE FROM custom_fields WHERE name='Total Flight Hours'"
snipeit_db_query "DELETE FROM custom_fieldsets WHERE name='UAV Metadata'"

# ---------------------------------------------------------------
# Set up necessary dependencies (Fieldset, Model, Supplier)
# ---------------------------------------------------------------
snipeit_db_query "INSERT INTO custom_fieldsets (name, created_at, updated_at) VALUES ('UAV Metadata', NOW(), NOW())"
FIELDSET_ID=$(snipeit_db_query "SELECT id FROM custom_fieldsets WHERE name='UAV Metadata' LIMIT 1" | tr -d '[:space:]')

snipeit_db_query "INSERT INTO manufacturers (name, created_at, updated_at) VALUES ('DJI', NOW(), NOW())"
MFG_ID=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='DJI' LIMIT 1" | tr -d '[:space:]')

snipeit_db_query "INSERT INTO categories (name, category_type, created_at, updated_at) VALUES ('Drones', 'asset', NOW(), NOW())"
CAT_ID=$(snipeit_db_query "SELECT id FROM categories WHERE name='Drones' LIMIT 1" | tr -d '[:space:]')

snipeit_db_query "INSERT INTO models (name, manufacturer_id, category_id, fieldset_id, created_at, updated_at) VALUES ('DJI Mavic 3 Enterprise', ${MFG_ID:-NULL}, ${CAT_ID:-NULL}, ${FIELDSET_ID:-NULL}, NOW(), NOW())"
MOD_ID=$(snipeit_db_query "SELECT id FROM models WHERE name='DJI Mavic 3 Enterprise' LIMIT 1" | tr -d '[:space:]')

snipeit_db_query "INSERT INTO suppliers (name, created_at, updated_at) VALUES ('DJI Enterprise Support', NOW(), NOW())"
SUP_ID=$(snipeit_db_query "SELECT id FROM suppliers WHERE name='DJI Enterprise Support' LIMIT 1" | tr -d '[:space:]')

SL_READY=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')

# ---------------------------------------------------------------
# Inject the 4 Drone Assets
# ---------------------------------------------------------------
for i in 1 2 3 4; do
    snipeit_db_query "INSERT INTO assets (asset_tag, name, model_id, status_id, purchase_date, purchase_cost, supplier_id, created_at, updated_at) VALUES ('DRONE-00$i', 'Survey Drone 0$i', ${MOD_ID:-NULL}, ${SL_READY:-NULL}, '2024-01-15', 5500.00, ${SUP_ID:-NULL}, NOW(), NOW())"
done

# ---------------------------------------------------------------
# Start Firefox and prepare UI
# ---------------------------------------------------------------
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000"
sleep 3

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="