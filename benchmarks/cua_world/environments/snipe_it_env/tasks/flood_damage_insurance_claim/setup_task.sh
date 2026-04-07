#!/bin/bash
echo "=== Setting up flood_damage_insurance_claim task ==="

source /workspace/scripts/task_utils.sh

get_id() {
    echo "$1" | jq -r '.payload.id // .id // empty' 2>/dev/null
}

# Ensure Desktop directory exists
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# 1. Gather/Create necessary location and statuses
LOC_DENVER=$(get_id "$(snipeit_api POST "locations" '{"name":"Denver Branch"}')")
if [ -z "$LOC_DENVER" ]; then LOC_DENVER=1; fi

SL_READY=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')
SL_REPAIR=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Out for Repair' LIMIT 1" | tr -d '[:space:]')
SL_LOST=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Lost/Stolen' LIMIT 1" | tr -d '[:space:]')

# Provide a generic model
MDL_GENERIC=$(get_id "$(snipeit_api POST "models" '{"name":"IT Equipment", "category_id":1}')")
if [ -z "$MDL_GENERIC" ]; then MDL_GENERIC=1; fi

# Clean up existing to be safe
for tag in ASSET-FD01 ASSET-FD02 ASSET-FD03 ASSET-FD04 ASSET-FD05 ASSET-FD06 ASSET-FD07; do
    snipeit_db_query "DELETE FROM assets WHERE asset_tag='$tag'" >/dev/null 2>&1
done

# 2. Inject target assets
echo "Injecting assets for Denver Branch..."
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-FD01\",\"name\":\"Dell Latitude 5540\",\"model_id\":$MDL_GENERIC,\"status_id\":$SL_READY,\"serial\":\"DL5540-FD001\",\"purchase_cost\":1200.00,\"rtd_location_id\":$LOC_DENVER}"
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-FD02\",\"name\":\"HP EliteDisplay E243\",\"model_id\":$MDL_GENERIC,\"status_id\":$SL_READY,\"serial\":\"HPE243-FD002\",\"purchase_cost\":350.00,\"rtd_location_id\":$LOC_DENVER}"
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-FD03\",\"name\":\"Cisco Catalyst 9200\",\"model_id\":$MDL_GENERIC,\"status_id\":$SL_READY,\"serial\":\"CC9200-FD003\",\"purchase_cost\":2800.00,\"rtd_location_id\":$LOC_DENVER}"
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-FD04\",\"name\":\"Dell PowerEdge R750\",\"model_id\":$MDL_GENERIC,\"status_id\":$SL_READY,\"serial\":\"DPR750-FD004\",\"purchase_cost\":8500.00,\"rtd_location_id\":$LOC_DENVER}"
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-FD05\",\"name\":\"Microsoft Surface Pro 9\",\"model_id\":$MDL_GENERIC,\"status_id\":$SL_READY,\"serial\":\"MSP9-FD005\",\"purchase_cost\":1600.00,\"rtd_location_id\":$LOC_DENVER}"
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-FD06\",\"name\":\"HP LaserJet Pro M404n\",\"model_id\":$MDL_GENERIC,\"status_id\":$SL_READY,\"serial\":\"HPLJ-FD006\",\"purchase_cost\":400.00,\"rtd_location_id\":$LOC_DENVER}"

# Inject distractor asset (also at Denver Branch, should NOT be modified)
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-FD07\",\"name\":\"Lenovo ThinkPad X1\",\"model_id\":$MDL_GENERIC,\"status_id\":$SL_READY,\"serial\":\"LENTP-FD007\",\"purchase_cost\":1500.00,\"rtd_location_id\":$LOC_DENVER}"

# 3. Record baseline state
echo "Recording baseline..."
snipeit_db_query "SELECT asset_tag, status_id, notes FROM assets WHERE deleted_at IS NULL" > /tmp/flood_baseline.txt
date +%s > /tmp/task_start_time.txt

# 4. Prepare UI
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000/hardware"
sleep 3
take_screenshot /tmp/task_initial.png

echo "=== setup complete ==="