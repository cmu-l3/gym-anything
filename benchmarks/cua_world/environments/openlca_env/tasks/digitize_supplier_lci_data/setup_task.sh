#!/bin/bash
set -e

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Digitize Supplier LCI Data task ==="

# 1. Create the Supplier Inventory Text File
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/supplier_inventory.txt << 'EOF'
************************************************************
SUPPLIER DATA SHEET - INJECTION MOLDING PROCESS
************************************************************
Process Name: Supplier Injection Molding
Region: US
Reference Product: Custom Plastic Part
Amount: 1.0 kg

--- INPUTS (FROM TECHNOSPHERE) ---
1. Material: Polypropylene resin
   Amount: 1.05 kg
   Source: USLCI "Polypropylene, resin, at plant"

2. Energy: Electricity
   Amount: 2.4 kWh
   Source: USLCI "Electricity, at grid, US"

3. Logistics: Transport to Customer
   Cargo Mass: 1.05 kg (Raw material weight transported)
   Distance: 500 km
   Mode: Combination Truck
   Source: USLCI "Transport, combination truck, diesel powered"
   NOTE: You must calculate the transport demand (Mass * Distance) in the appropriate unit (usually t*km)

--- OUTPUTS (ELEMENTARY FLOWS / EMISSIONS) ---
1. Emission to Air: VOC (Volatile Organic Compounds)
   Amount: 0.003 kg
   Category: Elementary Flows / Emission to air / unspecified
************************************************************
EOF
chmod 666 /home/ga/Documents/supplier_inventory.txt
chown ga:ga /home/ga/Documents/supplier_inventory.txt

# 2. Ensure USLCI database ZIP is available
IMPORT_DIR="/home/ga/LCA_Imports"
mkdir -p "$IMPORT_DIR"
USLCI_ZIP="$IMPORT_DIR/uslci_database.zip"

if [ ! -f "$USLCI_ZIP" ]; then
    if [ -f "/opt/openlca_data/uslci_database.zip" ]; then
        cp "/opt/openlca_data/uslci_database.zip" "$USLCI_ZIP"
        echo "Copied USLCI database to $USLCI_ZIP"
    else
        echo "WARNING: USLCI database not found in /opt!"
    fi
fi
chown -R ga:ga "$IMPORT_DIR"

# 3. Record Start Time
date +%s > /tmp/task_start_time.txt

# 4. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# 5. Maximize Window
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# 6. Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="