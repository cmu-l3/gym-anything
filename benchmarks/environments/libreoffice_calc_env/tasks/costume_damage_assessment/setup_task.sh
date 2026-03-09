#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Costume Damage Assessment Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not already available
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
# apt-get update -qq && apt-get install -y -qq python3-odf
fi

# Create the workbook with two sheets using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TableColumnProperties, TextProperties
from odf import number
import random

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# ===== SHEET 1: Master_Inventory =====
inventory_table = Table(name="Master_Inventory")

# Header row
header_row = TableRow()
headers = ["Costume_ID", "Item_Type", "Era", "Size", "Current_Condition", "Last_Used", "Rental_Value"]
for header in headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header))
    header_row.addElement(cell)
inventory_table.addElement(header_row)

# Sample costume inventory data (30 items)
costume_data = [
    ("C001", "Victorian Waistcoat", "Victorian", "M", "Good", "2024-01-10", "$45"),
    ("C002", "Edwardian Evening Gown", "Edwardian", "L", "Excellent", "2023-12-05", "$80"),
    ("C003", "Fairy Wings Large", "Fantasy", "One-Size", "Good", "2024-03-15", "$25"),
    ("C004", "Victorian Lady Dress", "Victorian", "M", "Good", "2024-02-20", "$65"),
    ("C005", "Men's Velvet Jacket", "Victorian", "L", "Excellent", "2024-01-30", "$55"),
    ("C006", "Medieval Tunic", "Medieval", "XL", "Good", "2023-11-12", "$30"),
    ("C007", "1920s Flapper Dress", "1920s", "S", "Excellent", "2024-02-14", "$50"),
    ("C008", "Victorian Top Hat", "Victorian", "One-Size", "Good", "2024-03-01", "$35"),
    ("C009", "Edwardian Suit Jacket", "Edwardian", "M", "Excellent", "2023-10-22", "$70"),
    ("C010", "Contemporary Blazer", "Contemporary", "L", "Excellent", "2024-03-10", "$40"),
    ("C011", "Victorian Smoking Jacket", "Victorian", "M", "Good", "2024-02-08", "$60"),
    ("C012", "Peasant Blouse", "Medieval", "M", "Good", "2023-12-18", "$20"),
    ("C013", "Edwardian Walking Suit", "Edwardian", "S", "Excellent", "2024-01-15", "$75"),
    ("C014", "Fairy Costume Complete", "Fantasy", "M", "Good", "2024-03-15", "$40"),
    ("C015", "Victorian Cravat", "Victorian", "One-Size", "Excellent", "2024-02-25", "$15"),
    ("C016", "Ball Gown Victorian", "Victorian", "L", "Good", "2023-11-30", "$95"),
    ("C017", "Men's Breeches", "Edwardian", "M", "Excellent", "2024-01-20", "$45"),
    ("C018", "Servant's Apron", "Victorian", "One-Size", "Good", "2024-02-10", "$12"),
    ("C019", "Military Coat", "Victorian", "L", "Good", "2023-12-22", "$85"),
    ("C020", "Renaissance Doublet", "Renaissance", "M", "Excellent", "2024-01-05", "$55"),
    ("C021", "Victorian Shawl", "Victorian", "One-Size", "Good", "2024-03-05", "$25"),
    ("C022", "1920s Suit", "1920s", "M", "Excellent", "2024-02-28", "$60"),
    ("C023", "Medieval Cloak", "Medieval", "L", "Good", "2023-11-08", "$35"),
    ("C024", "Edwardian Tea Dress", "Edwardian", "M", "Excellent", "2024-01-12", "$70"),
    ("C025", "Victorian Corset", "Victorian", "S", "Good", "2024-02-15", "$50"),
    ("C026", "Fairy Wings Small", "Fantasy", "One-Size", "Good", "2024-03-15", "$20"),
    ("C027", "Top Hat Black", "Victorian", "One-Size", "Excellent", "2024-03-01", "$30"),
    ("C028", "Victorian Bustle Dress", "Victorian", "L", "Good", "2023-12-30", "$90"),
    ("C029", "Edwardian Morning Coat", "Edwardian", "L", "Excellent", "2024-01-25", "$80"),
    ("C030", "Contemporary Casual", "Contemporary", "M", "Excellent", "2024-03-12", "$25"),
]

for item in costume_data:
    row = TableRow()
    for value in item:
        cell = TableCell(valuetype="string")
        cell.addElement(P(text=str(value)))
        row.addElement(cell)
    inventory_table.addElement(row)

doc.spreadsheet.addElement(inventory_table)

# ===== SHEET 2: Damage_Log =====
damage_table = Table(name="Damage_Log")

# Header
damage_header = TableRow()
damage_headers = ["Item Description", "Damage Notes", "Severity"]
for header in damage_headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header))
    damage_header.addElement(cell)
damage_table.addElement(damage_header)

# Informal damage reports (8 items)
damage_reports = [
    ("Velvet jacket, burgundy, size M", "Torn sleeve at shoulder seam, missing 2 buttons", "Poor"),
    ("Large fairy wings, iridescent", "Completely destroyed - wire frame bent, fabric torn beyond repair", "Unusable"),
    ("Victorian lady's dress, green, medium", "Heavy makeup stain on collar and cuff", "Fair"),
    ("Men's waistcoat, gray herringbone, L", "Seam split under right arm, loose buttons", "Fair"),
    ("Victorian shawl, lace", "Small tear in corner, minor snag", "Fair"),
    ("Top hat, black felt", "Crushed brim on left side, bent wire", "Poor"),
    ("Peasant blouse, cream colored", "Red wine stain on front, large", "Poor"),
    ("Walking suit (Edwardian, small)", "Hem coming undone, needs re-stitching", "Fair"),
]

for report in damage_reports:
    row = TableRow()
    for value in report:
        cell = TableCell(valuetype="string")
        cell.addElement(P(text=str(value)))
        row.addElement(cell)
    damage_table.addElement(row)

doc.spreadsheet.addElement(damage_table)

# Save the file
output_path = "/home/ga/Documents/costume_inventory.ods"
doc.save(output_path)
print(f"✅ Created costume inventory workbook: {output_path}")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/costume_inventory.ods
sudo chmod 666 /home/ga/Documents/costume_inventory.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/costume_inventory.ods > /tmp/calc_costume_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_costume_task.log || true
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

# Ensure we're on the Master_Inventory sheet (should be active by default)
sleep 0.5

echo "=== Costume Damage Assessment Task Setup Complete ==="
echo ""
echo "📋 Task Overview:"
echo "  - Master_Inventory sheet: 30 costume items"
echo "  - Damage_Log sheet: 8 damaged items from last show"
echo ""
echo "🎯 Your Tasks:"
echo "  1. Match damage reports to inventory items (switch sheets with sheet tabs)"
echo "  2. Update 'Current_Condition' for damaged items (Fair/Poor/Unusable)"
echo "  3. Add 'Repair_Urgency_Score' column with formula:"
echo "     - Poor=3pts, Fair=2pts, Good=1pt"
echo "     - Victorian/Edwardian era: +2pts (needed for next show)"
echo "     - High value (>$50): +1pt"
echo "  4. Add 'Repair_Priority' column flagging items with urgency ≥4 as 'URGENT'"
echo "  5. Calculate costume gap: count usable Victorian/Edwardian items"
echo "  6. Sort inventory by Repair_Urgency_Score (descending)"
echo ""
echo "⏰ Time limit: 180 seconds"