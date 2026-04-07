#!/bin/bash
echo "=== Setting up ewaste_donation_disposition task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# ---------------------------------------------------------------
# 1. Look up required Snipe-IT IDs
# ---------------------------------------------------------------
SL_RETIRED_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Retired' LIMIT 1" | tr -d '[:space:]')
SL_READY_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')

CAT_LAPTOPS_ID=$(snipeit_db_query "SELECT id FROM categories WHERE name='Laptops' LIMIT 1" | tr -d '[:space:]')
CAT_TABLETS_ID=$(snipeit_db_query "SELECT id FROM categories WHERE name='Tablets' LIMIT 1" | tr -d '[:space:]')
CAT_PRINTERS_ID=$(snipeit_db_query "SELECT id FROM categories WHERE name='Printers' LIMIT 1" | tr -d '[:space:]')

# Get or create Manufacturer
MAN_ID=$(snipeit_db_query "SELECT id FROM manufacturers LIMIT 1" | tr -d '[:space:]')
if [ -z "$MAN_ID" ]; then
    MAN_ID=$(get_id "$(snipeit_api POST "manufacturers" '{"name":"Generic"}')")
fi

# Get or create Models for the categories
MOD_LAPTOP_ID=$(snipeit_db_query "SELECT id FROM models WHERE category_id=$CAT_LAPTOPS_ID LIMIT 1" | tr -d '[:space:]')
if [ -z "$MOD_LAPTOP_ID" ]; then
    MOD_LAPTOP_ID=$(get_id "$(snipeit_api POST "models" "{\"name\":\"Generic Laptop\",\"category_id\":$CAT_LAPTOPS_ID,\"manufacturer_id\":$MAN_ID}")")
fi

MOD_TABLET_ID=$(snipeit_db_query "SELECT id FROM models WHERE category_id=$CAT_TABLETS_ID LIMIT 1" | tr -d '[:space:]')
if [ -z "$MOD_TABLET_ID" ]; then
    MOD_TABLET_ID=$(get_id "$(snipeit_api POST "models" "{\"name\":\"Generic Tablet\",\"category_id\":$CAT_TABLETS_ID,\"manufacturer_id\":$MAN_ID}")")
fi

MOD_PRINTER_ID=$(snipeit_db_query "SELECT id FROM models WHERE category_id=$CAT_PRINTERS_ID LIMIT 1" | tr -d '[:space:]')
if [ -z "$MOD_PRINTER_ID" ]; then
    MOD_PRINTER_ID=$(get_id "$(snipeit_api POST "models" "{\"name\":\"Generic Printer\",\"category_id\":$CAT_PRINTERS_ID,\"manufacturer_id\":$MAN_ID}")")
fi

# ---------------------------------------------------------------
# 2. Inject initial data
# ---------------------------------------------------------------
echo "  Injecting retired laptops (Target A)..."
snipeit_api POST "hardware" "{\"asset_tag\":\"LT-RET-01\",\"name\":\"Old Dev Laptop 1\",\"model_id\":$MOD_LAPTOP_ID,\"status_id\":$SL_RETIRED_ID}"
snipeit_api POST "hardware" "{\"asset_tag\":\"LT-RET-02\",\"name\":\"Old Dev Laptop 2\",\"model_id\":$MOD_LAPTOP_ID,\"status_id\":$SL_RETIRED_ID}"
snipeit_api POST "hardware" "{\"asset_tag\":\"LT-RET-03\",\"name\":\"Old Sales Laptop\",\"model_id\":$MOD_LAPTOP_ID,\"status_id\":$SL_RETIRED_ID}"
snipeit_api POST "hardware" "{\"asset_tag\":\"LT-RET-04\",\"name\":\"Old Exec Laptop\",\"model_id\":$MOD_LAPTOP_ID,\"status_id\":$SL_RETIRED_ID}"

echo "  Injecting retired tablets (Target B)..."
snipeit_api POST "hardware" "{\"asset_tag\":\"TAB-RET-01\",\"name\":\"Gen 3 Tablet A\",\"model_id\":$MOD_TABLET_ID,\"status_id\":$SL_RETIRED_ID,\"notes\":\"Good condition\"}"
snipeit_api POST "hardware" "{\"asset_tag\":\"TAB-RET-02\",\"name\":\"Gen 3 Tablet B\",\"model_id\":$MOD_TABLET_ID,\"status_id\":$SL_RETIRED_ID}"
snipeit_api POST "hardware" "{\"asset_tag\":\"TAB-RET-03\",\"name\":\"Gen 4 Tablet\",\"model_id\":$MOD_TABLET_ID,\"status_id\":$SL_RETIRED_ID}"

echo "  Injecting retired printers (Control Group)..."
snipeit_api POST "hardware" "{\"asset_tag\":\"PRN-RET-01\",\"name\":\"HQ Color Laser\",\"model_id\":$MOD_PRINTER_ID,\"status_id\":$SL_RETIRED_ID,\"notes\":\"Drum needs replacement\"}"
snipeit_api POST "hardware" "{\"asset_tag\":\"PRN-RET-02\",\"name\":\"Branch Printer\",\"model_id\":$MOD_PRINTER_ID,\"status_id\":$SL_RETIRED_ID}"

echo "  Injecting active assets (Noise Group)..."
snipeit_api POST "hardware" "{\"asset_tag\":\"LT-ACT-01\",\"name\":\"Current Dev Laptop\",\"model_id\":$MOD_LAPTOP_ID,\"status_id\":$SL_READY_ID}"
snipeit_api POST "hardware" "{\"asset_tag\":\"TAB-ACT-01\",\"name\":\"Current Field Tablet\",\"model_id\":$MOD_TABLET_ID,\"status_id\":$SL_READY_ID}"

sleep 2

# ---------------------------------------------------------------
# 3. Cleanup possible previous custom labels
# ---------------------------------------------------------------
snipeit_db_query "DELETE FROM status_labels WHERE name='Pending E-Waste' OR name='Donated'" 2>/dev/null || true

# ---------------------------------------------------------------
# 4. Record baseline timestamps and set up UI
# ---------------------------------------------------------------
date +%s > /tmp/ewaste_task_start.txt

ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000/hardware"
sleep 3
take_screenshot /tmp/ewaste_initial.png

echo "=== ewaste_donation_disposition task setup complete ==="