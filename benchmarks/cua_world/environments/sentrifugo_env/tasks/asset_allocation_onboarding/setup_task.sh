#!/bin/bash
echo "=== Setting up asset_allocation_onboarding task ==="

source /workspace/scripts/task_utils.sh

# Wait for Sentrifugo web service to be fully responsive
wait_for_http "$SENTRIFUGO_URL" 60

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# CLEAN UP PRIOR RUNS
# Ensure a clean slate so the agent must do the work itself
# ==============================================================================
echo "Cleaning up any prior run artifacts from the database..."

# Remove any previously created categories
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo \
    -e "DELETE FROM main_assetcategories WHERE categoryname IN ('Laptops', 'Mobile Devices');" \
    2>/dev/null || true

# Remove any previously created assets matching the manifest serials
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo \
    -e "DELETE FROM main_assets WHERE assetcode LIKE '%2026%' OR serialnumber LIKE '%2026%' OR assetname LIKE '%MacBook%' OR assetname LIKE '%Dell%' OR assetname LIKE '%iPhone%' OR assetname LIKE '%Samsung%';" \
    2>/dev/null || true

# Remove any lingering allocation records for these employees/assets
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo \
    -e "DELETE FROM main_assetallocations WHERE comments LIKE '%2026%';" \
    2>/dev/null || true

# ==============================================================================
# PREPARE TASK DATA
# Write the manifest file to the Desktop
# ==============================================================================
mkdir -p /home/ga/Desktop
MANIFEST_PATH="/home/ga/Desktop/it_equipment_manifest.txt"

cat > "$MANIFEST_PATH" << 'EOF'
=========================================================
IT EQUIPMENT ALLOCATION MANIFEST - Q1 2026
=========================================================

STEP 1: ASSET CATEGORIES
Please ensure the following Asset Categories exist in the system:
1. Laptops
2. Mobile Devices

STEP 2: NEW ASSETS & ALLOCATIONS
Add the following assets and allocate them to the designated employees.

Asset 1
- Asset Name: MacBook Pro 16-inch
- Category: Laptops
- Serial Number / Asset Code: MBP-2026-X1
- Vendor: Apple Inc.
- Allocated To: EMP005 (David Kim)

Asset 2
- Asset Name: Dell Latitude 7420
- Category: Laptops
- Serial Number / Asset Code: DELL-2026-Y2
- Vendor: Dell Technologies
- Allocated To: EMP012 (Jennifer Martinez)

Asset 3
- Asset Name: iPhone 15 Pro
- Category: Mobile Devices
- Serial Number / Asset Code: IPH-2026-Z3
- Vendor: Apple Inc.
- Allocated To: EMP005 (David Kim)

Asset 4
- Asset Name: Samsung Galaxy S24
- Category: Mobile Devices
- Serial Number / Asset Code: SAM-2026-W4
- Vendor: Samsung Electronics
- Allocated To: EMP019 (Tyler Moore)

Note: Map the serial numbers to either the "Serial Number", "Asset Code", or "Invoice Number" field depending on the available system form fields. Ensure the status is marked as Active/Allocated.
EOF

chown ga:ga "$MANIFEST_PATH"
echo "Manifest written to $MANIFEST_PATH"

# ==============================================================================
# APPLICATION SETUP
# Launch Firefox and log in to Sentrifugo
# ==============================================================================
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}"
sleep 3

# Take initial screenshot proving the clean starting state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="