#!/bin/bash
set -euo pipefail

echo "=== Setting up Menu Engineering Analysis task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Source shared utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# Clean up previous artifacts
rm -f /home/ga/Documents/Spreadsheets/menu_engineering_analysis.xlsx 2>/dev/null || true
rm -f /tmp/onlyoffice_*.log 2>/dev/null || true
pkill -f "onlyoffice-desktopeditors" 2>/dev/null || true
sleep 1

# Ensure workspace directories exist
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo mkdir -p /var/lib/onlyoffice/ground_truth

echo "Generating source data files..."

# Python script to generate realistic deterministic data
cat > /tmp/generate_menu_data.py << 'PYEOF'
#!/usr/bin/env python3
import csv
import random
import os
from datetime import datetime, timedelta
import json

random.seed(2024)

OUTPUT_DIR = "/home/ga/Documents/Spreadsheets"
GT_DIR = "/var/lib/onlyoffice/ground_truth"

MENU_ITEMS = [
    ("Crispy Calamari", "Appetizer", 3.25, 13.00),
    ("French Onion Soup", "Appetizer", 2.10, 9.50),
    ("Bruschetta Trio", "Appetizer", 2.85, 12.00),
    ("Spinach Artichoke Dip", "Appetizer", 2.40, 11.00),
    ("Shrimp Cocktail", "Appetizer", 5.80, 15.00),
    ("Caesar Salad", "Appetizer", 2.15, 10.50),
    ("Soup of the Day", "Appetizer", 1.65, 7.50),
    ("Grilled Atlantic Salmon", "Entree", 8.20, 24.00),
    ("NY Strip Steak 12oz", "Entree", 12.50, 32.00),
    ("Chicken Marsala", "Entree", 5.10, 19.00),
    ("Penne Vodka", "Entree", 3.20, 16.00),
    ("Pan-Seared Sea Bass", "Entree", 10.75, 28.00),
    ("BBQ Baby Back Ribs", "Entree", 8.90, 23.00),
    ("Mushroom Risotto", "Entree", 3.85, 17.00),
    ("Fish and Chips", "Entree", 5.60, 16.50),
    ("Herb-Roasted Chicken", "Entree", 4.45, 18.00),
    ("Lobster Ravioli", "Entree", 7.30, 22.00),
    ("Beef Bourguignon", "Entree", 7.80, 21.00),
    ("Eggplant Parmesan", "Entree", 3.50, 15.50),
    ("Classic Burger", "Sandwich", 4.10, 14.50),
    ("Grilled Chicken Club", "Sandwich", 3.90, 13.50),
    ("Philly Cheesesteak", "Sandwich", 5.25, 15.00),
    ("Ahi Tuna Wrap", "Sandwich", 6.00, 14.00),
    ("Pulled Pork Sandwich", "Sandwich", 3.70, 13.00),
    ("Tiramisu", "Dessert", 2.90, 10.00),
    ("Chocolate Lava Cake", "Dessert", 3.10, 11.00),
    ("New York Cheesecake", "Dessert", 2.50, 9.50),
    ("Crème Brûlée", "Dessert", 2.20, 9.00),
    ("Apple Crisp à la Mode", "Dessert", 2.65, 9.50),
    ("Seasonal Fruit Tart", "Dessert", 3.40, 10.50),
]

POPULARITY_WEIGHTS = [
    0.85, 0.60, 0.55, 0.90, 0.40, 1.10, 0.70,
    1.20, 0.75, 1.30, 1.00, 0.35, 0.95, 0.45, 1.05, 1.15, 0.55, 0.65, 0.80,
    1.40, 1.10, 0.70, 0.30, 0.85,
    0.75, 0.90, 1.00, 0.60, 0.50, 0.35,
]

# Write recipe cards
with open(os.path.join(OUTPUT_DIR, "recipe_cost_cards.csv"), 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["Item_Name", "Category", "Plate_Cost_USD", "Menu_Price_USD"])
    for item in MENU_ITEMS:
        writer.writerow([item[0], item[1], f"{item[2]:.2f}", f"{item[3]:.2f}"])

# Generate POS data
transactions = []
start_date = datetime(2024, 6, 3)

for day_offset in range(28):
    current_date = start_date + timedelta(days=day_offset)
    day_of_week = current_date.weekday()
    
    if day_of_week in [4, 5]: base_covers = random.randint(90, 130)
    elif day_of_week == 6: base_covers = random.randint(70, 100)
    elif day_of_week == 0: base_covers = random.randint(50, 75)
    else: base_covers = random.randint(65, 95)
    
    total_weight = sum(POPULARITY_WEIGHTS)
    for i, (item_name, category, plate_cost, menu_price) in enumerate(MENU_ITEMS):
        expected_qty = (POPULARITY_WEIGHTS[i] / total_weight) * base_covers
        if category == "Appetizer": expected_qty *= 0.55
        elif category == "Entree": expected_qty *= 0.85
        elif category == "Sandwich": expected_qty *= 0.40
        elif category == "Dessert": expected_qty *= 0.30
        
        qty = max(0, int(expected_qty + random.gauss(0, expected_qty * 0.3)))
        if qty > 0:
            actual_price = menu_price
            if random.random() < 0.03:
                actual_price = round(menu_price * random.uniform(0.5, 0.85), 2)
            transactions.append([
                current_date.strftime("%Y-%m-%d"),
                current_date.strftime("%A"),
                item_name, category, qty,
                f"{actual_price:.2f}", f"{actual_price * qty:.2f}"
            ])

with open(os.path.join(OUTPUT_DIR, "pos_sales_4weeks.csv"), 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["Date", "Day_of_Week", "Item_Name", "Category", "Quantity_Sold", "Unit_Price_USD", "Line_Total_USD"])
    for txn in transactions:
        writer.writerow(txn)

print("Data generated successfully.")
PYEOF

python3 /tmp/generate_menu_data.py
chown -R ga:ga "$WORKSPACE_DIR"

# Launch ONLYOFFICE
echo "Starting ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors --new:cell > /tmp/onlyoffice_menu_task.log 2>&1 &"

# Wait for application window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "ONLYOFFICE\|Desktop Editors"; then
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "ONLYOFFICE" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Desktop Editors" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ONLYOFFICE" 2>/dev/null || true

sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="