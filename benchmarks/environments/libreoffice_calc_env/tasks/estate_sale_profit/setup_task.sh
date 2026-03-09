#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Estate Sale Profit Calculator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create messy estate sale CSV with realistic inconsistent data
cat > /home/ga/Documents/estate_sale_inventory.csv << 'CSVEOF'
Item,Asking Price,Status,Notes
Antique oak dresser,250,SOLD,sold for $220
Coffee table,75,sold,Sold to neighbor $75
China cabinet,180,Available,
Lawn mower,120,SOLD,$100
Box of old books,15,sold,sold 15
Vintage brass lamp,45,SOLD,Tom bought it for 40
Dining chairs set of 4,200,Available,
Kitchen mixer,35,SOLD,$35
Garden tools lot,25,sold,25
Desk chair,50,Available,
Bookshelf,85,SOLD,sold for $80
Area rug 8x10,95,sold,$90
Microwave,40,SOLD,sold for 40
Picture frames box,20,sold,sold $20
Sofa,300,Available,
Floor lamp pair,60,SOLD,55
Cooking pots set,30,sold,sold to Mary for $30
Coffee maker,25,Available,
Wall mirror large,70,SOLD,$65
Throw pillows,15,sold,15
Bedside tables,110,Available,
Tool chest,150,SOLD,sold for $140
Vacuum cleaner,65,sold,$60
Folding chairs 6pc,45,SOLD,sold for 45
Decorative vases,18,Available,
Camping tent,80,sold,$75
Bicycle,95,SOLD,sold for $90
Kitchen dishes set,40,sold,sold 40
Table lamp,28,Available,
Printer,55,SOLD,50
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/estate_sale_inventory.csv
sudo chmod 664 /home/ga/Documents/estate_sale_inventory.csv

echo "✅ Created estate_sale_inventory.csv with 30 items"

# Launch LibreOffice Calc with the CSV
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/estate_sale_inventory.csv > /tmp/calc_estate_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_estate_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
fi

# Click on center of the screen to select current desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 400 click 1" || true
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

# Position cursor at cell A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Estate Sale Profit Calculator Task Setup Complete ==="
echo ""
echo "📋 SCENARIO: Maria held an estate sale this weekend and needs to know"
echo "   if she made the \$2,000 needed for her moving truck deposit."
echo ""
echo "📝 TASK INSTRUCTIONS:"
echo "  1. Examine the messy data - Status has variations: SOLD, sold, Available"
echo "  2. Notes has mixed formats: '\$50', 'sold for 45', 'Tom bought it for 40'"
echo "  3. Create a new column (E) titled 'Actual Sale Price'"
echo "  4. Add formulas to extract sale price IF item is sold, else 0"
echo "  5. Handle case-insensitive 'sold' detection (LOWER, SEARCH functions)"
echo "  6. Parse numbers from text (VALUE, SUBSTITUTE functions)"
echo "  7. Calculate Total Revenue (SUM of Actual Sale Prices)"
echo "  8. Add Goal comparison: Did we reach \$2,000?"
echo "  9. Show 'Goal Met: YES/NO' with surplus/shortfall amount"
echo ""
echo "💡 HINTS:"
echo "  - Use IF(OR(LOWER(C2)=\"sold\",ISNUMBER(SEARCH(\"sold\",LOWER(C2)))),..."
echo "  - Use VALUE(SUBSTITUTE(D2,\"\$\",\"\")) to extract numbers"
echo "  - Expected total: ~\$2,150 (exceeds goal)"
echo "  - Focus on formulas, not hard-coding values"