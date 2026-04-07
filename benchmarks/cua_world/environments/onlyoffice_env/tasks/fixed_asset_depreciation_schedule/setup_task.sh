#!/bin/bash
set -euo pipefail

echo "=== Setting up Fixed Asset Depreciation Schedule Task ==="

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_ts

# Kill any existing ONLYOFFICE processes
pkill -f "onlyoffice-desktopeditors|DesktopEditors" 2>/dev/null || true
sleep 1

# Setup directories
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Clean up any potential existing output files
rm -f "$WORKSPACE_DIR/depreciation_schedule_2023.xlsx" 2>/dev/null || true

# Generate the Source CSV file
cat > /tmp/create_fixed_assets.py << 'PYEOF'
import csv

assets = [
    ["asset_id", "description", "category", "date_acquired", "cost_basis", "salvage_value", "useful_life_years", "macrs_class", "convention"],
    ["FA-001", "CNC Milling Machine A", "Machinery", "2018-03-15", 250000, 25000, 10, 7, "HY"],
    ["FA-002", "Ford F-150 Pickup", "Vehicles", "2019-06-10", 45000, 5000, 5, 5, "HY"],
    ["FA-003", "Dell PowerEdge Server", "Computer Equipment", "2020-01-20", 35000, 2000, 5, 5, "HY"],
    ["FA-004", "Office Desks & Chairs", "Furniture", "2020-05-14", 28000, 3000, 7, 7, "HY"],
    ["FA-005", "Parking Lot Resurfacing", "Land Improvements", "2020-08-30", 85000, 0, 15, 15, "HY"],
    ["FA-006", "HVAC System Upgrade", "Building Improvements", "2020-10-05", 150000, 10000, 20, 39, "MM"],
    ["FA-007", "CNC Lathe Machine", "Machinery", "2021-02-18", 320000, 40000, 10, 7, "HY"],
    ["FA-008", "Warehouse Forklift", "Machinery", "2021-04-22", 38000, 5000, 7, 7, "HY"],
    ["FA-009", "Executive Office Suite", "Furniture", "2021-07-11", 42000, 5000, 7, 7, "HY"],
    ["FA-010", "Network Switches", "Computer Equipment", "2021-09-05", 18000, 1000, 5, 5, "HY"],
    ["FA-011", "Chevy Silverado 2500", "Vehicles", "2021-11-20", 52000, 8000, 5, 5, "HY"],
    ["FA-012", "Laser Cutting Machine", "Machinery", "2022-01-15", 485000, 50000, 10, 7, "HY"],
    ["FA-013", "Assembly Line Conveyor", "Machinery", "2022-03-10", 125000, 15000, 10, 7, "HY"],
    ["FA-014", "Security Camera System", "Computer Equipment", "2022-05-25", 24000, 2000, 5, 5, "HY"],
    ["FA-015", "Breakroom Appliances", "Furniture", "2022-06-18", 12000, 1000, 7, 7, "HY"],
    ["FA-016", "Roof Replacement", "Building Improvements", "2022-08-05", 210000, 0, 20, 39, "MM"],
    ["FA-017", "Delivery Box Truck", "Vehicles", "2022-09-12", 68000, 10000, 5, 5, "HY"],
    ["FA-018", "Robotic Welding Arm", "Machinery", "2023-01-20", 275000, 35000, 10, 7, "HY"],
    ["FA-019", "Employee Laptops (50)", "Computer Equipment", "2023-02-15", 75000, 5000, 3, 5, "HY"],
    ["FA-020", "Conference Room Table", "Furniture", "2023-03-10", 15000, 2000, 7, 7, "HY"],
    ["FA-021", "Quality Control Scanner", "Computer Equipment", "2023-04-05", 45000, 5000, 5, 5, "HY"],
    ["FA-022", "Toyota Prius (Sales)", "Vehicles", "2023-05-22", 32000, 5000, 5, 5, "HY"],
    ["FA-023", "Hydraulic Press", "Machinery", "2023-06-18", 145000, 20000, 10, 7, "HY"],
    ["FA-024", "Exterior Lighting", "Land Improvements", "2023-07-12", 28000, 0, 15, 15, "HY"],
    ["FA-025", "Air Compressor Unit", "Machinery", "2023-08-05", 35000, 5000, 7, 7, "HY"],
    ["FA-026", "Server Rack Cooling", "Computer Equipment", "2023-08-20", 22000, 2000, 5, 5, "HY"],
    ["FA-027", "Ford Transit Van", "Vehicles", "2023-09-10", 48000, 8000, 5, 5, "HY"],
    ["FA-028", "Shop Floor Scrubber", "Machinery", "2023-09-20", 18500, 2000, 5, 7, "HY"],
]

with open('/home/ga/Documents/Spreadsheets/pmg_fixed_assets.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(assets)
PYEOF
python3 /tmp/create_fixed_assets.py
chown ga:ga /home/ga/Documents/Spreadsheets/pmg_fixed_assets.csv

# Generate MACRS Tables reference file
cat > /home/ga/Documents/macrs_tables.txt << 'EOF'
IRS MACRS PERCENTAGE TABLES (Publication 946)
General Depreciation System (GDS)

Table A-1: 3-, 5-, 7-, 10-, 15-, and 20-Year Property
Half-Year Convention, 200% DB transitioning to Straight Line
Year | 5-Year | 7-Year | 15-Year
1    | 20.00% | 14.29% | 5.00%
2    | 32.00% | 24.49% | 9.50%
3    | 19.20% | 17.49% | 8.55%
4    | 11.52% | 12.49% | 7.70%
5    | 11.52% |  8.93% | 6.93%
6    |  5.76% |  8.92% | 6.23%
7    |        |  8.93% | 5.90%
8    |        |  4.46% | 5.90%
9    |        |        | 5.91%
10   |        |        | 5.90%
11   |        |        | 5.91%
12   |        |        | 5.90%
13   |        |        | 5.91%
14   |        |        | 5.90%
15   |        |        | 5.91%
16   |        |        | 2.95%

Table A-7a: 39-Year Nonresidential Real Property
Mid-Month Convention, Straight Line
(Simplified for full years after placement)
Year 1: 2.461% (Average assumption for mid-year placement)
Years 2-39: 2.564%
Year 40: Varies
EOF
chown ga:ga /home/ga/Documents/macrs_tables.txt

# Start ONLYOFFICE desktop editors
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors &"
sleep 5

# Ensure window is visible and maximized
DISPLAY=:1 wmctrl -r "Desktop Editors" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Desktop Editors" 2>/dev/null || true

# Capture initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="