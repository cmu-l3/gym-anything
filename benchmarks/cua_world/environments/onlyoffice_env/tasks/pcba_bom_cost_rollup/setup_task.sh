#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up PCBA BOM Cost Rollup Task ==="

# Record task start timestamp for anti-gaming checks
echo $(date +%s) > /tmp/pcba_cost_rollup_start_ts

cleanup_temp_files
kill_onlyoffice ga
sleep 1

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

CSV_PATH="$WORKSPACE_DIR/iot_gateway_bom.csv"

# Python script to generate deterministic CSV data
cat > /tmp/create_bom_data.py << 'PYEOF'
#!/usr/bin/env python3
import csv
import sys

output_path = sys.argv[1]

headers = [
    "Item_No", "Reference_Designator", "Quantity", "Manufacturer", 
    "Part_Number", "Description", "Category", "Unit_Cost_1k", 
    "Lifecycle_Status", "Sole_Source"
]

# Deterministic data modeling exactly: Total=$38.45, Sole_Source=$14.30, Obsolete/NRND=4
rows = [
    ["1", "U1", 1, "Espressif", "ESP32-WROVER-E", "Wi-Fi + BT MCU Module", "IC", 2.80, "Active", "Yes"],
    ["2", "U2", 1, "Microchip", "LAN8720A-CP-TR", "10/100 Ethernet Transceiver", "IC", 1.15, "Active", "No"],
    ["3", "U3", 1, "NXP", "MCIMX6G2CVM05AB", "i.MX 6ULL Applications Processor", "IC", 8.50, "Active", "Yes"],
    ["4", "U4", 1, "Texas Instruments", "TPS65217CRSLR", "PMIC for i.MX", "IC", 2.50, "Active", "No"],
    ["5", "U5", 1, "Micron", "MT41K256M16TW-107", "4Gb DDR3L SDRAM", "IC", 3.50, "Active", "No"],
    ["6", "U6", 1, "Winbond", "W25Q128JVSIQ", "128Mb SPI Flash", "IC", 1.25, "Obsolete", "No"],
    ["7", "U7", 1, "Semtech", "SX1302", "LoRa Baseband Processor", "IC", 1.80, "Active", "No"],
    ["8", "U8", 1, "Maxim", "DS1307ZN+", "I2C Real-Time Clock", "IC", 1.00, "Obsolete", "No"],
    ["9", "J1, J2", 2, "Molex", "43045-0400", "Micro-Fit 3.0 Header 4 Pos", "Connector", 0.60, "NRND", "No"],
    ["10", "J3, J4", 2, "Linx", "CONSMA001-G", "SMA RF Connector Edge Mount", "Connector", 1.50, "Active", "Yes"],
    ["11", "L1-L4", 4, "Wurth", "744311150", "Inductor 1.5uH 10A", "Passive", 0.45, "Active", "No"],
    ["12", "C1-C50", 50, "Kemet", "C0805C104K5RACTU", "Cap Ceramic 0.1uF 50V", "Passive", 0.012, "Active", "No"],
    ["13", "R1-R60", 60, "Yageo", "RC0603FR-0710KL", "Resistor 10K Ohm 1%", "Passive", 0.005, "Active", "No"],
    ["14", "D1-D5", 5, "Diodes Inc", "B340A-13-F", "Schottky Rectifier 40V 3A", "Diode", 0.15, "NRND", "No"],
    ["15", "PCB1", 1, "Generic", "4-LAYER-FR4-HASL", "Custom 4-Layer PCBA", "PCB", 8.30, "Active", "No"]
]

with open(output_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(headers)
    writer.writerows(rows)
PYEOF

sudo -u ga python3 /tmp/create_bom_data.py "$CSV_PATH"

# Launch ONLYOFFICE with the generated CSV
echo "Launching ONLYOFFICE Spreadsheet Editor..."
sudo -u ga DISPLAY=:1 onlyoffice-desktopeditors "$CSV_PATH" > /dev/null 2>&1 &
sleep 5

# Maximize the window for visibility
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take an initial screenshot for VLM/trajectory verification
DISPLAY=:1 scrot /tmp/pcba_cost_rollup_initial_screenshot.png 2>/dev/null || true

echo "=== Task setup complete ==="