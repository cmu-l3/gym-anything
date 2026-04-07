#!/bin/bash
echo "=== Setting up lab_equipment_fleet_onboarding task ==="

source /workspace/scripts/task_utils.sh

# 1. Cleanup any pre-existing task entities to ensure a clean slate and prevent gaming
echo "Cleaning up any existing task entities..."
snipeit_db_query "DELETE FROM assets WHERE asset_tag IN ('LAB-0001', 'LAB-0002', 'LAB-0003', 'LAB-0004')"
snipeit_db_query "DELETE FROM models WHERE name IN ('DSOX1204G Oscilloscope', '34465A Digital Multimeter')"
snipeit_db_query "DELETE FROM categories WHERE name='Lab Instruments'"
snipeit_db_query "DELETE FROM manufacturers WHERE name='Keysight Technologies'"
snipeit_db_query "DELETE FROM suppliers WHERE name='Fisher Scientific'"
snipeit_db_query "DELETE FROM locations WHERE name='Engineering Lab 204'"

# 2. Record start time for logging purposes
date +%s > /tmp/task_start_time.txt

# 3. Start Firefox and navigate to Snipe-IT
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000"
sleep 3

# 4. Take initial screenshot showing clean dashboard state
take_screenshot /tmp/fleet_onboarding_initial.png

echo "=== lab_equipment_fleet_onboarding setup complete ==="