#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Emergency Supply Rotation Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Calculate dates for realistic test data
# We'll use Python to generate dates relative to today
python3 << 'PYEOF'
from datetime import datetime, timedelta
import csv

today = datetime.now()

# Create test data with various expiration scenarios
supplies = [
    # Item Name, Category, Purchase Date, Expiration Date, Quantity, Location
    ["Bottled Water (24-pack)", "Water", (today - timedelta(days=685)).strftime("%Y-%m-%d"), (today + timedelta(days=45)).strftime("%Y-%m-%d"), "1 case", "Garage"],
    ["Canned Beans", "Food", (today - timedelta(days=695)).strftime("%Y-%m-%d"), (today + timedelta(days=400)).strftime("%Y-%m-%d"), "12 cans", "Pantry"],
    ["AA Batteries (alkaline)", "Batteries", (today - timedelta(days=1810)).strftime("%Y-%m-%d"), (today + timedelta(days=15)).strftime("%Y-%m-%d"), "8 pack", "Drawer"],
    ["First Aid Antibiotic Ointment", "First Aid", (today - timedelta(days=740)).strftime("%Y-%m-%d"), (today - timedelta(days=10)).strftime("%Y-%m-%d"), "2 tubes", "Cabinet"],
    ["Emergency Food Bars", "Food", (today - timedelta(days=1817)).strftime("%Y-%m-%d"), (today + timedelta(days=8)).strftime("%Y-%m-%d"), "6 bars", "Cabinet"],
    ["D-cell Batteries (lithium)", "Batteries", (today - timedelta(days=150)).strftime("%Y-%m-%d"), (today + timedelta(days=2500)).strftime("%Y-%m-%d"), "4 pack", "Drawer"],
    ["Bottled Water (second case)", "Water", (today - timedelta(days=365)).strftime("%Y-%m-%d"), "", "1 case", "Basement"],  # Missing expiration - needs calculation
    ["Canned Soup", "Food", (today - timedelta(days=915)).strftime("%Y-%m-%d"), (today + timedelta(days=180)).strftime("%Y-%m-%d"), "8 cans", "Pantry"],
    ["Adhesive Bandages", "First Aid", (today - timedelta(days=730)).strftime("%Y-%m-%d"), "", "1 box", "Cabinet"],  # Missing expiration - needs calculation
    ["Flashlight Batteries (alkaline)", "Batteries", (today - timedelta(days=1750)).strftime("%Y-%m-%d"), (today + timedelta(days=75)).strftime("%Y-%m-%d"), "4 pack", "Garage"],
    ["Pain Reliever (Ibuprofen)", "Medicine", (today - timedelta(days=702)).strftime("%Y-%m-%d"), (today + timedelta(days=28)).strftime("%Y-%m-%d"), "1 bottle", "Cabinet"],
    ["Emergency Blanket", "Gear", (today - timedelta(days=1500)).strftime("%Y-%m-%d"), (today + timedelta(days=900)).strftime("%Y-%m-%d"), "2 blankets", "Garage"],
]

# Write CSV
with open('/home/ga/Documents/emergency_supplies_partial.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['Item Name', 'Category', 'Purchase Date', 'Expiration Date', 'Quantity', 'Location', 'Days Until Expiration', 'Status'])
    for supply in supplies:
        writer.writerow(supply + ['', ''])  # Empty formula columns

print("✅ Created emergency_supplies_partial.csv with realistic dates")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/emergency_supplies_partial.csv
sudo chmod 666 /home/ga/Documents/emergency_supplies_partial.csv

# Create instruction sheet with shelf life reference
cat > /home/ga/Documents/shelf_life_reference.txt << 'EOF'
STANDARD SHELF LIFE REFERENCE
==============================

Bottled Water: 2 years (730 days)
Canned Goods: 3 years (1095 days)
Batteries (alkaline): 5 years (1825 days)
Batteries (lithium): 10 years (3650 days)
First Aid Ointments: 2 years (730 days)
Bandages: 5 years (1825 days)
Emergency Food Bars: 5 years (1825 days)

Use this reference to calculate missing expiration dates.
EOF

sudo chown ga:ga /home/ga/Documents/shelf_life_reference.txt

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc with emergency supplies data..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/emergency_supplies_partial.csv > /tmp/calc_emergency_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_emergency_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
fi

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Calc window
echo "Focusing Calc window..."
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Ensure cursor is at A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Emergency Supply Rotation Task Setup Complete ==="
echo ""
echo "📋 TASK INSTRUCTIONS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Fill missing Expiration Dates (rows with blank dates)"
echo "   - Use Purchase Date + shelf life from reference"
echo "   - Bottled Water: +730 days, Bandages: +1825 days"
echo ""
echo "2. Create 'Days Until Expiration' formula in column G:"
echo "   =DAYS(D2,TODAY()) or =D2-TODAY()"
echo ""
echo "3. Create 'Status' formula in column H:"
echo "   =IF(G2<0,\"EXPIRED\",IF(G2<=30,\"IMMEDIATE\",IF(G2<=90,\"SOON\",\"OK\")))"
echo ""
echo "4. Apply conditional formatting to columns G and H"
echo "   - G: Color scale (red→yellow→green)"
echo "   - H: Text-based colors (EXPIRED=red, IMMEDIATE=orange, SOON=yellow, OK=green)"
echo ""
echo "5. Sort all data by column G (Days) ascending"
echo ""
echo "💡 Shelf life reference saved to: ~/Documents/shelf_life_reference.txt"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"