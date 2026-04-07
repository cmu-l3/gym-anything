#!/bin/bash
echo "=== Setting up industrial_asset_inventory_digitization task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60

# Record task start time for anti-gaming
date +%s > /tmp/task_start_timestamp

# ---- Clean up the Assets module database tables ----
log "Cleaning up existing asset data to ensure a clean slate..."
# Delete in order to respect any potential foreign key constraints
sentrifugo_db_root_query "DELETE FROM main_assets;" 2>/dev/null || true
sentrifugo_db_root_query "DELETE FROM main_assetvendors;" 2>/dev/null || true
sentrifugo_db_root_query "DELETE FROM main_assetcategories;" 2>/dev/null || true
log "Asset module tables cleared."

# ---- Create the equipment manifest on the Desktop ----
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/new_equipment_manifest.txt << 'MANIFEST'
GREEN-TECH BIOMASS POWER PLANT
Industrial Asset Inventory Manifest
Date: March 10, 2026
======================================================

We are modernizing our tracking of expensive safety equipment. 
Please register the following newly acquired items into the Sentrifugo HRMS Assets module.

IMPORTANT: You must create the Categories and the Vendor in the system FIRST before you can add the actual assets.

STEP 1: CREATE ASSET CATEGORIES
-------------------------------
Please add the following three categories to the system:
1. Two-Way Radios
2. Gas Detectors
3. Thermal Cameras

STEP 2: CREATE VENDOR
-------------------------------
Add our new safety equipment supplier to the vendors list:
Vendor Name   : Industrial Safety Supply Co.
Contact Email : sales@industrialsafety.local
Contact Phone : 555-0198

STEP 3: REGISTER ASSETS
-------------------------------
Now, register the three new pieces of equipment. Link each to its correct Category and Vendor.

Asset 1:
- Asset Name   : Motorola XPR 7550e
- Serial Number: RAD-8821-A
- Category     : Two-Way Radios

Asset 2:
- Asset Name   : Honeywell BW Ultra
- Serial Number: GAS-9910-B
- Category     : Gas Detectors

Asset 3:
- Asset Name   : FLIR K55
- Serial Number: THM-4450-C
- Category     : Thermal Cameras

======================================================
MANIFEST

chown ga:ga /home/ga/Desktop/new_equipment_manifest.txt
log "Equipment manifest created at ~/Desktop/new_equipment_manifest.txt"

# ---- Navigate to Sentrifugo Dashboard ----
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/dashboard"
sleep 3
take_screenshot /tmp/task_start_screenshot.png

log "Task ready: Manifest on Desktop, Assets module DB tables empty."
echo "=== Setup complete ==="