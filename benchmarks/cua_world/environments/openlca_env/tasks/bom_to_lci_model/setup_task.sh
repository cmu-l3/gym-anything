#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up BOM to LCI Model Task ==="

# 1. Create the Bill of Materials (BOM) file
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/kettle_bom.csv << 'EOF'
Component,Material_Spec,Amount,Unit
Polypropylene Casing,Polypropylene resin,0.85,kg
Steel Heating Element,Stainless steel cold rolled,0.45,kg
Copper Wiring,Copper wire,0.12,kg
Assembly Electricity,Electricity at grid,1.5,kWh
Corrugated Packaging,Corrugated container,0.3,kg
EOF
chown ga:ga /home/ga/Documents/kettle_bom.csv

echo "Created BOM at /home/ga/Documents/kettle_bom.csv"

# 2. Ensure Results directory exists
mkdir -p /home/ga/LCA_Results
chown ga:ga /home/ga/LCA_Results
# Remove any existing output from previous runs
rm -f /home/ga/LCA_Results/kettle_impact.csv

# 3. Ensure Import files are ready
mkdir -p /home/ga/LCA_Imports
if [ -f "/opt/openlca_data/uslci_database.zip" ]; then
    cp /opt/openlca_data/uslci_database.zip /home/ga/LCA_Imports/
fi
if [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
    cp /opt/openlca_data/lcia_methods.zip /home/ga/LCA_Imports/
fi
chown -R ga:ga /home/ga/LCA_Imports

# 4. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 5. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# 6. Setup Window
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# 7. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="