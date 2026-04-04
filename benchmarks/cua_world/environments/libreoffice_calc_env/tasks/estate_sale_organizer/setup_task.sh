#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Estate Sale Organizer Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not present
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
    apt-get update && apt-get install -y python3-odf
fi

# Create the messy estate sale spreadsheet with 3 source sheets
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Sheet 1: Main_Inventory (40+ items with mixed price formats)
inventory_data = [
    ["Item", "Description", "Estimated_Value"],
    ["Antique Oak Dresser", "6-drawer dresser, 1920s", "$200-300"],
    ["Grandmother's China Set", "Complete 12-place setting", "around 500"],
    ["Vintage Typewriter", "Royal portable, working", "75"],
    ["Leather Armchair", "Brown leather, well-worn", "150 to 200"],
    ["Crystal Chandelier", "10-light fixture", "$400-500"],
    ["Wedding Album", "1955 leather-bound", "priceless"],
    ["Tool Set", "Complete mechanic's tools", "around 250"],
    ["Dining Table", "Oak, seats 8", "300-400"],
    ["Military Medals", "WWII service medals", ""],
    ["Quilt Collection", "5 handmade quilts", "200"],
    ["Vinyl Record Collection", "200+ records, 1960s-70s", "around 300"],
    ["Antique Mirror", "Gilt frame, 4ft tall", "$150-200"],
    ["Garden Tools", "Shovels, rakes, etc", "50"],
    ["Kitchen Appliances", "Mixer, toaster, blender", "around 80"],
    ["Book Collection", "First editions, classics", "500-700"],
    ["Grandfather Clock", "Working, chimes", "$800-1000"],
    ["Sewing Machine", "Singer, vintage", "125"],
    ["Painting Set", "Oils, canvases, easel", "100 to 150"],
    ["Piano", "Upright, needs tuning", "around 600"],
    ["Area Rugs", "Persian style, 3 rugs", "400-600"],
    ["Silverware Set", "Sterling silver, service for 12", "$350-450"],
    ["Wicker Furniture", "Patio set, 4 pieces", "200"],
    ["Camping Gear", "Tent, sleeping bags, etc", "around 150"],
    ["Christmas Decorations", "Vintage ornaments", "75-100"],
    ["Wall Clock Collection", "8 decorative clocks", "around 120"],
    ["Ceramic Figurines", "20+ pieces", "50 to 100"],
    ["Photo Albums", "Family photos, 1940s-1980s", ""],
    ["Telescope", "Amateur astronomy scope", "around 200"],
    ["Bicycle", "Vintage Schwinn", "150-200"],
    ["Cookware Set", "Cast iron and copper", "around 175"],
    ["Jewelry Box", "Wooden, with costume jewelry", "100-150"],
    ["Fishing Gear", "Rods, tackle box", "80"],
    ["Lamp Collection", "Table and floor lamps, 6 pieces", "around 200"],
    ["Luggage Set", "Vintage leather, 5 pieces", "150-250"],
    ["Board Game Collection", "Classic games, complete", "50"],
    ["Sports Equipment", "Golf clubs, tennis rackets", "around 150"],
    ["Antique Radio", "Tube radio, 1940s", "125-175"],
    ["Blanket Chest", "Cedar chest, 1930s", "around 225"],
    ["Desk", "Roll-top desk, oak", "300-400"],
    ["Office Chair", "Leather executive chair", "100"],
    ["File Cabinet", "Metal, 4-drawer", "around 75"],
    ["Bookshelf", "Oak, 6-shelf unit", "150-200"]
]

table1 = Table(name="Main_Inventory")
for row_data in inventory_data:
    row = TableRow()
    for cell_value in row_data:
        cell = TableCell()
        p = P(text=str(cell_value))
        cell.addElement(p)
        row.addElement(cell)
    table1.addElement(row)
doc.spreadsheet.addElement(table1)

# Sheet 2: Family_Promises (15 items, 3-4 with conflicts)
promises_data = [
    ["Item_Name", "Promised_To"],
    ["Antique Oak Dresser", "John"],
    ["Antique Oak Dresser", "Sarah"],  # CONFLICT!
    ["Grandmother's China Set", "Mary"],
    ["Leather Armchair", "Tom"],
    ["Crystal Chandelier", "John"],
    ["Tool Set", "David"],
    ["Dining Table", "Sarah"],
    ["Quilt Collection", "Mary"],
    ["Quilt Collection", "Elizabeth"],  # CONFLICT!
    ["Grandfather Clock", "Tom"],
    ["Piano", "Sarah"],
    ["Piano", "Michael"],  # CONFLICT!
    ["Silverware Set", "Mary"],
    ["Telescope", "David"],
    ["Telescope", "Robert"],  # CONFLICT!
    ["Desk", "Michael"]
]

table2 = Table(name="Family_Promises")
for row_data in promises_data:
    row = TableRow()
    for cell_value in row_data:
        cell = TableCell()
        p = P(text=str(cell_value))
        cell.addElement(p)
        row.addElement(cell)
    table2.addElement(row)
doc.spreadsheet.addElement(table2)

# Sheet 3: Sentimental_Keep (8 items that cannot be sold)
sentimental_data = [
    ["Item", "Reason"],
    ["Wedding Album", "Family history"],
    ["Military Medals", "Father's service"],
    ["Photo Albums", "Irreplaceable memories"],
    ["Grandmother's China Set", "Heirloom - changed mind"],
    ["Grandfather Clock", "Family tradition"],
    ["Piano", "Children learned on this"],
    ["Quilt Collection", "Handmade by grandmother"],
    ["Jewelry Box", "Mother's personal items"]
]

table3 = Table(name="Sentimental_Keep")
for row_data in sentimental_data:
    row = TableRow()
    for cell_value in row_data:
        cell = TableCell()
        p = P(text=str(cell_value))
        cell.addElement(p)
        row.addElement(cell)
    table3.addElement(row)
doc.spreadsheet.addElement(table3)

# Save the file
output_path = "/home/ga/Documents/estate_inventory.ods"
doc.save(output_path)
print(f"✅ Created estate inventory spreadsheet: {output_path}")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/estate_inventory.ods
sudo chmod 666 /home/ga/Documents/estate_inventory.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc with estate inventory..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/estate_inventory.ods > /tmp/calc_estate_task.log 2>&1 &"

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

# Navigate to first sheet (Main_Inventory)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Estate Sale Organizer Task Setup Complete ==="
echo ""
echo "📋 URGENT TASK: Estate sale in 3 days!"
echo ""
echo "📝 Your mission:"
echo "  1. Create 'Consolidated' sheet merging all inventory data"
echo "  2. Detect items promised to MULTIPLE family members (conflicts!)"
echo "  3. Mark sentimental items as 'DO NOT SELL'"
echo "  4. Parse messy prices into Low/High numeric ranges"
echo "  5. Create 'For_Sale' sheet with ONLY sellable items"
echo "  6. Create 'Urgent_Conflicts' sheet for family discussion"
echo "  7. Calculate total estimated sale value"
echo ""
echo "⚠️  CRITICAL: Items in Sentimental_Keep CANNOT be sold!"
echo "⚠️  Items promised to multiple people need URGENT resolution!"
echo ""
echo "💡 Hints:"
echo "  - Use VLOOKUP/COUNTIF to cross-reference sheets"
echo "  - Watch for items appearing multiple times in Family_Promises"
echo "  - Parse prices: '$50-75' → Low:50, High:75"
echo "  - 'around 100' → Low:90, High:110 (±10%)"