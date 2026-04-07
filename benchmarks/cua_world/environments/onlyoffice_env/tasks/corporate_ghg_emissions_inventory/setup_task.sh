#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up GHG Emissions Inventory Task ==="

# Record task start timestamp for anti-gaming
echo $(date +%s) > /tmp/ghg_inventory_start_ts

cleanup_temp_files
kill_onlyoffice ga
sleep 1

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
DESKTOP_DIR="/home/ga/Desktop"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$DESKTOP_DIR"

# Generate deterministic realistic dataset (150 rows)
cat > /tmp/create_ghg_data.py << 'PYEOF'
import csv
import random

# Seed guarantees deterministic verification mapping
random.seed(2023)
with open("/home/ga/Documents/Spreadsheets/nyc_building_energy_2022.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["Property_ID", "Property_Name", "Electricity_Use_kBtu", "Natural_Gas_Use_kBtu", "Fuel_Oil_2_Use_kBtu"])
    for i in range(1, 151):
        elec = round(random.uniform(500000, 20000000), 2)
        gas = round(random.uniform(100000, 10000000), 2)
        # Not all buildings use fuel oil
        oil = round(random.uniform(50000, 5000000), 2) if random.random() > 0.6 else 0.0
        writer.writerow([f"NYC-{1000+i}", f"Property_{i:03d}", elec, gas, oil])
PYEOF

python3 /tmp/create_ghg_data.py
chown ga:ga "$WORKSPACE_DIR/nyc_building_energy_2022.csv"

# Create Reference Text for the agent
cat > "$DESKTOP_DIR/epa_emission_factors.txt" << 'EOF'
=== EPA GHG Emission Factors (2023 Reference) ===

UNIT CONVERSIONS:
- Electricity: 1 MWh = 3,412.14 kBtu
- Natural Gas & Fuel Oil: 1 mmBtu = 1,000 kBtu

EPA EMISSION FACTORS (eGRID 2023 & Subpart C):
- Scope 2 (NYCW eGRID subregion): 552.8 lbs CO2e per MWh
- Scope 1 (Natural Gas): 53.11 kg CO2e per mmBtu
- Scope 1 (Fuel Oil #2): 74.21 kg CO2e per mmBtu

MASS CONVERSIONS (To Metric Tons - MT):
- 1 Metric Ton (MT) = 2,204.62 lbs
- 1 Metric Ton (MT) = 1,000 kg

REQUIRED OUTPUT:
Calculate Scope 1 and Scope 2 emissions for all properties in Metric Tons of CO2 equivalent (MTCO2e).
EOF
chown ga:ga "$DESKTOP_DIR/epa_emission_factors.txt"

# Launch OnlyOffice with the CSV loaded
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$WORKSPACE_DIR/nyc_building_energy_2022.csv' > /tmp/onlyoffice.log 2>&1 &"

# Wait for window and maximize
wait_for_window "ONLYOFFICE\|Desktop Editors" 30
focus_onlyoffice_window || true
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Setup Complete ==="