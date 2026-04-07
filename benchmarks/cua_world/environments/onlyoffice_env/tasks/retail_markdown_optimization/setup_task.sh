#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Retail Markdown Optimization Task ==="

# Record start time for anti-gaming
echo $(date +%s) > /tmp/retail_markdown_start_ts

# Clean up environment
cleanup_temp_files
kill_onlyoffice ga
sleep 1

# Setup workspace
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

CSV_PATH="$WORKSPACE_DIR/fw_inventory_sales.csv"

# Generate dataset using Python
cat > /tmp/create_inventory_data.py << 'PYEOF'
#!/usr/bin/env python3
import csv
import sys
import random

output_path = sys.argv[1]
random.seed(12345)

departments = ["Outerwear", "Knitwear", "Denim", "Accessories", "Footwear"]
categories_map = {
    "Outerwear": ["Coats", "Jackets", "Vests", "Parkas"],
    "Knitwear": ["Sweaters", "Cardigans", "Turtlenecks", "Hoodies"],
    "Denim": ["Jeans", "Shorts", "Jackets", "Skirts"],
    "Accessories": ["Hats", "Scarves", "Gloves", "Belts"],
    "Footwear": ["Boots", "Sneakers", "Loafers", "Heels"]
}

with open(output_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow([
        "SKU", "Department", "Category", "Unit_Cost", "Ticket_Price", 
        "Units_Sold_Season", "Units_On_Hand", "Weeks_On_Floor"
    ])
    
    for i in range(1, 1001):
        sku = f"FW24-{i:04d}"
        dept = random.choice(departments)
        category = random.choice(categories_map[dept])
        
        unit_cost = round(random.uniform(10.0, 80.0), 2)
        ticket_price = round(unit_cost * random.uniform(2.5, 4.0), 2)
        
        # Ensure non-zero values for weeks and sales to prevent div/0 errors
        weeks_on_floor = random.randint(2, 24)
        units_sold = random.randint(10, 500)
        units_on_hand = random.randint(5, 300)
        
        writer.writerow([
            sku, dept, category, unit_cost, ticket_price, 
            units_sold, units_on_hand, weeks_on_floor
        ])

print(f"Generated {output_path} successfully.")
PYEOF

sudo -u ga python3 /tmp/create_inventory_data.py "$CSV_PATH"

# Launch ONLYOFFICE with the CSV file
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$CSV_PATH' > /tmp/onlyoffice_task.log 2>&1 &"

# Wait for ONLYOFFICE window to appear
echo "Waiting for application window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Desktop Editors\|ONLYOFFICE"; then
        echo "Window detected."
        break
    fi
    sleep 1
done

# Maximize and focus the window
sleep 2
WID=$(DISPLAY=:1 wmctrl -l | grep -i "Desktop Editors\|ONLYOFFICE" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any popup dialogs
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1

# Take initial screenshot
su - ga -c "DISPLAY=:1 scrot /tmp/retail_markdown_initial.png" 2>/dev/null || true

echo "=== Task Setup Complete ==="