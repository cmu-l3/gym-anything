#!/bin/bash
echo "=== Setting up fleet_telematics_installation task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# 1. Clean up target tags/models to enforce fresh creation by the agent
echo "  Cleaning up old data..."
for tag in DASH-01 DASH-02 DASH-03 ELD-01 ELD-02 ELD-03; do
    snipeit_db_query "DELETE FROM assets WHERE asset_tag='$tag'"
done
for i in {101..115}; do
    snipeit_db_query "DELETE FROM assets WHERE asset_tag='VEH-${i}'"
done
snipeit_db_query "DELETE FROM models WHERE name IN ('CM31 Dashcam', 'VG34 ELD')"
snipeit_db_query "DELETE FROM manufacturers WHERE name='Samsara'"
snipeit_db_query "DELETE FROM categories WHERE name='Telematics'"

# 2. Inject fleet vehicles natively via DB to ensure rapid, bulletproof setup
echo "  Injecting fleet vehicles..."

# Get or create Vehicles category
CAT_VEHICLE=$(snipeit_db_query "SELECT id FROM categories WHERE name='Vehicles' LIMIT 1" | tr -d '[:space:]')
if [ -z "$CAT_VEHICLE" ]; then
    snipeit_db_query "INSERT INTO categories (name, category_type, created_at, updated_at) VALUES ('Vehicles', 'asset', NOW(), NOW())"
    CAT_VEHICLE=$(snipeit_db_query "SELECT id FROM categories WHERE name='Vehicles' LIMIT 1" | tr -d '[:space:]')
fi

# Get or create Ford manufacturer
MAN_FORD=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Ford' LIMIT 1" | tr -d '[:space:]')
if [ -z "$MAN_FORD" ]; then
    snipeit_db_query "INSERT INTO manufacturers (name, created_at, updated_at) VALUES ('Ford', NOW(), NOW())"
    MAN_FORD=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Ford' LIMIT 1" | tr -d '[:space:]')
fi

# Get or create Transit model
MDL_TRANSIT=$(snipeit_db_query "SELECT id FROM models WHERE name='Transit 250' LIMIT 1" | tr -d '[:space:]')
if [ -z "$MDL_TRANSIT" ]; then
    snipeit_db_query "INSERT INTO models (name, manufacturer_id, category_id, created_at, updated_at) VALUES ('Transit 250', $MAN_FORD, $CAT_VEHICLE, NOW(), NOW())"
    MDL_TRANSIT=$(snipeit_db_query "SELECT id FROM models WHERE name='Transit 250' LIMIT 1" | tr -d '[:space:]')
fi

# Get Status ID for Ready to Deploy
SL_READY=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')

# Seed the 15 fleet vehicles
for i in {101..115}; do
    TAG="VEH-${i}"
    EXISTS=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE asset_tag='$TAG'" | tr -d '[:space:]')
    if [ "$EXISTS" -eq 0 ]; then
        snipeit_db_query "INSERT INTO assets (asset_tag, name, model_id, status_id, created_at, updated_at) VALUES ('$TAG', 'Delivery Van $i', $MDL_TRANSIT, $SL_READY, NOW(), NOW())"
    fi
done

sleep 2

# 3. Ensure Firefox is running and focused on Snipe-IT
ensure_firefox_snipeit
sleep 2

# Navigate to dashboard
navigate_firefox_to "http://localhost:8000"
sleep 3

# Take initial screenshot for evidence
take_screenshot /tmp/telematics_initial.png

echo "=== fleet_telematics_installation task setup complete ==="