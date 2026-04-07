#!/bin/bash
echo "=== Setting up manufacturer_data_cleanup task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up potential existing task data to ensure idempotency
echo "Cleaning up any existing task data..."
snipeit_db_query "DELETE FROM assets WHERE asset_tag LIKE 'MFR-CLN-%'" 2>/dev/null || true
snipeit_db_query "DELETE FROM models WHERE name IN ('OptiPlex 7090', 'Latitude 5520', 'ProBook 450 G8', 'EliteDisplay E243', 'ThinkPad X1 Carbon Gen 9', 'Catalyst 9300')" 2>/dev/null || true
snipeit_db_query "DELETE FROM manufacturers WHERE name IN ('Dell', 'Dell Inc.', 'HP Inc.', 'Hewlett-Packard', 'Lenovo', 'Lenovo Group', 'Cisco Systems')" 2>/dev/null || true

# 2. Setup categories if they don't exist
ensure_category() {
    local name="$1"
    local type="$2"
    local cat_id=$(snipeit_db_query "SELECT id FROM categories WHERE name='$name' LIMIT 1" | tr -d '[:space:]')
    if [ -z "$cat_id" ]; then
        snipeit_api POST "categories" "{\"name\":\"$name\",\"category_type\":\"$type\"}" > /dev/null
        cat_id=$(snipeit_db_query "SELECT id FROM categories WHERE name='$name' LIMIT 1" | tr -d '[:space:]')
    fi
    echo "$cat_id"
}

CAT_DESKTOPS=$(ensure_category "Desktops" "asset")
CAT_LAPTOPS=$(ensure_category "Laptops" "asset")
CAT_MONITORS=$(ensure_category "Monitors" "asset")
CAT_NETWORKING=$(ensure_category "Networking" "asset")
SL_READY=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')

# 3. Create Canonical Manufacturers
echo "Creating Canonical Manufacturers..."
snipeit_api POST "manufacturers" '{"name":"Dell"}' > /dev/null
snipeit_api POST "manufacturers" '{"name":"HP Inc."}' > /dev/null
snipeit_api POST "manufacturers" '{"name":"Lenovo"}' > /dev/null

CANON_DELL=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Dell' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
CANON_HP=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='HP Inc.' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
CANON_LENOVO=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Lenovo' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')

echo "$CANON_DELL" > /tmp/mfr_canon_dell.txt
echo "$CANON_HP" > /tmp/mfr_canon_hp.txt
echo "$CANON_LENOVO" > /tmp/mfr_canon_lenovo.txt

# 4. Create Duplicate Manufacturers
echo "Creating Duplicate Manufacturers..."
snipeit_api POST "manufacturers" '{"name":"Dell Inc."}' > /dev/null
snipeit_api POST "manufacturers" '{"name":"Hewlett-Packard"}' > /dev/null
snipeit_api POST "manufacturers" '{"name":"Lenovo Group"}' > /dev/null

DUP_DELL=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Dell Inc.' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
DUP_HP=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Hewlett-Packard' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
DUP_LENOVO=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Lenovo Group' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')

echo "$DUP_DELL" > /tmp/mfr_dup_dell.txt
echo "$DUP_HP" > /tmp/mfr_dup_hp.txt
echo "$DUP_LENOVO" > /tmp/mfr_dup_lenovo.txt

# 5. Create Models assigned to the DUPLICATE manufacturers
echo "Creating Models..."
snipeit_api POST "models" "{\"name\":\"OptiPlex 7090\",\"manufacturer_id\":$DUP_DELL,\"category_id\":$CAT_DESKTOPS}" > /dev/null
snipeit_api POST "models" "{\"name\":\"Latitude 5520\",\"manufacturer_id\":$DUP_DELL,\"category_id\":$CAT_LAPTOPS}" > /dev/null
snipeit_api POST "models" "{\"name\":\"ProBook 450 G8\",\"manufacturer_id\":$DUP_HP,\"category_id\":$CAT_LAPTOPS}" > /dev/null
snipeit_api POST "models" "{\"name\":\"EliteDisplay E243\",\"manufacturer_id\":$DUP_HP,\"category_id\":$CAT_MONITORS}" > /dev/null
snipeit_api POST "models" "{\"name\":\"ThinkPad X1 Carbon Gen 9\",\"manufacturer_id\":$DUP_LENOVO,\"category_id\":$CAT_LAPTOPS}" > /dev/null

MOD_OPTI=$(snipeit_db_query "SELECT id FROM models WHERE name='OptiPlex 7090' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
MOD_LAT=$(snipeit_db_query "SELECT id FROM models WHERE name='Latitude 5520' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
MOD_PRO=$(snipeit_db_query "SELECT id FROM models WHERE name='ProBook 450 G8' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
MOD_ELI=$(snipeit_db_query "SELECT id FROM models WHERE name='EliteDisplay E243' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
MOD_THI=$(snipeit_db_query "SELECT id FROM models WHERE name='ThinkPad X1 Carbon Gen 9' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')

# 6. Create Assets to ensure models can't be carelessly deleted without orphaning
echo "Creating Assets..."
snipeit_api POST "hardware" "{\"asset_tag\":\"MFR-CLN-001\",\"name\":\"Desktop Setup 1\",\"model_id\":$MOD_OPTI,\"status_id\":$SL_READY}" > /dev/null
snipeit_api POST "hardware" "{\"asset_tag\":\"MFR-CLN-002\",\"name\":\"Laptop Setup 1\",\"model_id\":$MOD_LAT,\"status_id\":$SL_READY}" > /dev/null
snipeit_api POST "hardware" "{\"asset_tag\":\"MFR-CLN-003\",\"name\":\"Laptop Setup 2\",\"model_id\":$MOD_PRO,\"status_id\":$SL_READY}" > /dev/null
snipeit_api POST "hardware" "{\"asset_tag\":\"MFR-CLN-004\",\"name\":\"Monitor Setup 1\",\"model_id\":$MOD_ELI,\"status_id\":$SL_READY}" > /dev/null
snipeit_api POST "hardware" "{\"asset_tag\":\"MFR-CLN-005\",\"name\":\"Laptop Setup 3\",\"model_id\":$MOD_THI,\"status_id\":$SL_READY}" > /dev/null

# 7. Start Firefox and take initial screenshot
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000/hardware"
sleep 3
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="