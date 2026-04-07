#!/bin/bash
echo "=== Setting up event_equipment_location_checkout task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# ---------------------------------------------------------------
# 1. Pre-load required assets for the task
# ---------------------------------------------------------------
echo "  Injecting AV assets..."

# Get a valid model ID to use for the hardware assets
MDL_ID=$(snipeit_db_query "SELECT id FROM models LIMIT 1" | tr -d '[:space:]')
if [ -z "$MDL_ID" ]; then
    echo "  Creating fallback model..."
    snipeit_api POST "models" '{"name":"Generic AV Equipment", "category_id":1, "manufacturer_id":1}'
    MDL_ID=$(snipeit_db_query "SELECT id FROM models WHERE name='Generic AV Equipment' LIMIT 1" | tr -d '[:space:]')
fi

# Get the ID for "Ready to Deploy" status
SL_READY_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')

TARGETS=("AV-PROJ-01" "AV-PROJ-02" "AV-MIC-01" "AV-MIC-02" "AV-MIC-03" "AV-MIC-04" "AV-SW-01")
UNRELATED=("AV-PROJ-03" "AV-MIC-05")

# Ensure assets are clean and injected
for tag in "${TARGETS[@]}" "${UNRELATED[@]}"; do
    if asset_exists_by_tag "$tag"; then
        snipeit_db_query "DELETE FROM assets WHERE asset_tag='$tag'"
    fi
    
    # Assign appropriate names
    if [[ "$tag" == *"PROJ"* ]]; then
        NAME="Panasonic PT-RZ12K Projector"
    elif [[ "$tag" == *"MIC"* ]]; then
        NAME="Shure ULXD4Q Wireless Mic"
    else
        NAME="Blackmagic ATEM Video Switcher"
    fi
    
    # Create the asset using the Snipe-IT API
    snipeit_api POST "hardware" "{\"asset_tag\":\"$tag\", \"name\":\"$NAME\", \"status_id\":$SL_READY_ID, \"model_id\":$MDL_ID}"
done
sleep 2

# Remove the target location if it somehow exists from a previous run
if [ $(snipeit_db_query "SELECT COUNT(*) FROM locations WHERE name='Main Auditorium'" | tr -d '[:space:]') -gt 0 ]; then
    snipeit_db_query "DELETE FROM locations WHERE name='Main Auditorium'"
fi

# ---------------------------------------------------------------
# 2. Record Initial State
# ---------------------------------------------------------------
date +%s > /tmp/task_start_time.txt
echo "Initial setup complete."

# ---------------------------------------------------------------
# 3. Ensure Firefox is running and on Snipe-IT
# ---------------------------------------------------------------
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000"
sleep 3
take_screenshot /tmp/event_checkout_initial.png

echo "=== event_equipment_location_checkout task setup complete ==="
echo "Task: Create Location 'Main Auditorium' and checkout 7 specific AV assets to it."