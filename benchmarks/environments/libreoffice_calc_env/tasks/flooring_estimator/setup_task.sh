#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Flooring Estimator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create instructions file with task details
cat > /home/ga/Documents/flooring_instructions.txt << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                    FLOORING ESTIMATION PROJECT                               ║
╚══════════════════════════════════════════════════════════════════════════════╝

You are planning to install laminate flooring in three rooms of your home.

ROOM MEASUREMENTS (Base Square Footage):
┌──────────────┬────────────────────────────────────┬──────────────┐
│ Room         │ Dimensions                         │ Square Feet  │
├──────────────┼────────────────────────────────────┼──────────────┤
│ Living Room  │ 15ft × 12ft + 6ft × 4ft (L-shape) │ 204 sq ft    │
│ Bedroom      │ 12ft × 11ft (rectangular)          │ 132 sq ft    │
│ Hallway      │ 18ft × 3.5ft (rectangular)         │  63 sq ft    │
└──────────────┴────────────────────────────────────┴──────────────┘

MATERIAL SPECIFICATIONS:
• Laminate flooring: $2.89 per square foot
• Flooring boxes: Each box covers 20 square feet
• Underlayment: $0.45 per square foot

WASTE FACTORS (Industry Standard):
• Irregular shapes (L-shaped): Add 15% extra material
• Rectangular rooms: Add 10% extra material
• Underlayment: No waste factor needed

YOUR TASK - Create a spreadsheet that calculates:

1. Adjusted square footage for each room (base area + waste factor)
   Formula: base_sqft × (1 + waste_factor)
   
2. Number of flooring boxes needed (MUST round UP to whole boxes)
   Formula: CEILING(adjusted_sqft / 20) or ROUNDUP(adjusted_sqft / 20, 0)
   
3. Cost of flooring for each room
   Formula: adjusted_sqft × $2.89
   
4. Cost of underlayment for each room
   Formula: base_sqft × $0.45  (no waste factor for underlayment)
   
5. Total room cost (flooring + underlayment)

6. Project totals (sum of all rooms)

EXPECTED RESULTS:
• Living Room: ~235 sq ft adjusted, 12 boxes, ~$770 total
• Bedroom: ~145 sq ft adjusted, 8 boxes, ~$480 total
• Hallway: ~69 sq ft adjusted, 4 boxes, ~$230 total
• Grand Total: ~$1,477

SAVE YOUR WORK AS: /home/ga/Documents/flooring_estimate.ods

═══════════════════════════════════════════════════════════════════════════════
EOF

chown ga:ga /home/ga/Documents/flooring_instructions.txt

# Create a starter template ODS file with headers to help the agent
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TextProperties, TableColumnProperties, TableCellProperties
from odf.number import NumberStyle, CurrencyStyle, CurrencySymbol, Number, Text as NumText

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet
table = Table(name="Flooring Estimate")
doc.spreadsheet.addElement(table)

# Helper function to create cell with text
def create_text_cell(text):
    cell = TableCell()
    p = P(text=str(text))
    cell.addElement(p)
    return cell

# Add header row with column labels (optional - makes it easier for agent)
header_row = TableRow()
headers = ["Room Name", "Base Sq Ft", "Waste %", "Adjusted Sq Ft", "Boxes Needed", "Flooring Cost", "Underlayment Cost", "Total Cost"]
for header in headers:
    header_row.addElement(create_text_cell(header))
table.addElement(header_row)

# Add 5 empty rows for data entry (3 rooms + 1 blank + 1 totals)
for _ in range(10):
    row = TableRow()
    for _ in range(len(headers)):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Save the file
doc.save("/home/ga/Documents/flooring_estimate.ods")
print("✅ Created starter template with headers")
PYEOF

# Set correct permissions
chown ga:ga /home/ga/Documents/flooring_estimate.ods
chmod 666 /home/ga/Documents/flooring_estimate.ods

echo "✅ Created flooring estimate template and instructions"

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/flooring_estimate.ods > /tmp/calc_flooring.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_flooring.log
    # Don't exit, continue anyway
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit, continue anyway
fi

# Click on center of the screen to select current desktop (important for focus)
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

# Position cursor at A2 (first data row, after header)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key Down
sleep 0.2

# Display instructions in a text window (non-blocking)
echo "Displaying instructions..."
su - ga -c "DISPLAY=:1 zenity --text-info --title='Flooring Estimator - Instructions' --filename=/home/ga/Documents/flooring_instructions.txt --width=700 --height=600 &" || true

echo "=== Flooring Estimator Task Setup Complete ==="
echo ""
echo "📐 Task: Create flooring material calculator"
echo "📋 Instructions displayed in separate window"
echo "📊 Template spreadsheet opened with headers"
echo ""
echo "Key requirements:"
echo "  • Calculate adjusted square footage with waste factors"
echo "  • Use CEILING/ROUNDUP for box quantities (must round up!)"
echo "  • Calculate flooring cost (uses adjusted sq ft)"
echo "  • Calculate underlayment cost (uses base sq ft, no waste)"
echo "  • Create totals with SUM functions"
echo "  • Expected total: ~$1,477"