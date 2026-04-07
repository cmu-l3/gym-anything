#!/bin/bash
echo "=== Setting up status_label_taxonomy_restructuring task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record timestamp
date +%s > /tmp/task_start_time.txt

# Wait for DB to be accessible
sleep 2

# ---------------------------------------------------------------
# 1. Fetch reference IDs
# ---------------------------------------------------------------
MDL_ID=$(snipeit_db_query "SELECT id FROM models LIMIT 1" | tr -d '[:space:]')
if [ -z "$MDL_ID" ]; then MDL_ID=1; fi

SL_READY=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')
if [ -z "$SL_READY" ]; then SL_READY=1; fi

# ---------------------------------------------------------------
# 2. Inject Target Setup Data (Locations & Suppliers)
# ---------------------------------------------------------------
echo "Injecting target Locations and Suppliers..."
snipeit_db_query "INSERT INTO locations (name, created_at, updated_at) VALUES ('Build Room', NOW(), NOW());"
LOC_BUILD=$(snipeit_db_query "SELECT id FROM locations WHERE name='Build Room' LIMIT 1" | tr -d '[:space:]')

snipeit_db_query "INSERT INTO suppliers (name, created_at, updated_at) VALUES ('TechFix Partners', NOW(), NOW());"
SUP_TECHFIX=$(snipeit_db_query "SELECT id FROM suppliers WHERE name='TechFix Partners' LIMIT 1" | tr -d '[:space:]')

# ---------------------------------------------------------------
# 3. Inject Assets
# ---------------------------------------------------------------
echo "Injecting target assets for re-classification..."

# Group 1: Build Room assets -> Awaiting Build
for i in 1 2 3; do
    snipeit_db_query "INSERT INTO assets (asset_tag, name, model_id, status_id, rtd_location_id, created_at, updated_at) VALUES ('ASSET-BR0$i', 'Workstation Chassis $i', $MDL_ID, $SL_READY, $LOC_BUILD, NOW(), NOW());"
done

# Group 2: TechFix Supplier assets -> Vendor Repair
for i in 1 2 3; do
    snipeit_db_query "INSERT INTO assets (asset_tag, name, model_id, status_id, supplier_id, created_at, updated_at) VALUES ('ASSET-TF0$i', 'Network Switch $i', $MDL_ID, $SL_READY, $SUP_TECHFIX, NOW(), NOW());"
done

# Group 3: Security Hold notes -> Security Review
for i in 1 2 3; do
    snipeit_db_query "INSERT INTO assets (asset_tag, name, model_id, status_id, notes, created_at, updated_at) VALUES ('ASSET-SH0$i', 'Executive Laptop $i', $MDL_ID, $SL_READY, 'Confiscated - Flagged for Security Hold pending investigation', NOW(), NOW());"
done

# Group 4: Disposal Approved notes -> Disposed
for i in 1 2; do
    snipeit_db_query "INSERT INTO assets (asset_tag, name, model_id, status_id, notes, created_at, updated_at) VALUES ('ASSET-DA0$i', 'Obsolete Server $i', $MDL_ID, $SL_READY, 'E-waste pick-up requested. Disposal Approved per IT director.', NOW(), NOW());"
done

# Group 5: Noise Assets (Standard deployable assets) -> Should NOT be touched
echo "Injecting noise assets..."
for i in 1 2 3 4 5; do
    snipeit_db_query "INSERT INTO assets (asset_tag, name, model_id, status_id, created_at, updated_at) VALUES ('ASSET-NS0$i', 'Standard Display $i', $MDL_ID, $SL_READY, NOW(), NOW());"
done

# Clean up any previously created ITSM labels if they exist (to ensure a clean slate)
snipeit_db_query "DELETE FROM status_labels WHERE name LIKE 'ITSM - %'"

# ---------------------------------------------------------------
# 4. Prepare UI
# ---------------------------------------------------------------
echo "Launching Firefox..."
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000/hardware"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="