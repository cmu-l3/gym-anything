#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Health Insurance Decision Rescue Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with messy insurance plan data
cat > /home/ga/Documents/insurance_plans_raw.csv << 'CSVEOF'
Plan Name,Monthly Premium,Deductible,Co-insurance %,Out-of-Pocket Max,PCP Visit Cost,Specialist Visit Cost,Generic Rx Cost
Gold PPO,450,1000,20,6500,25,50,15
Silver HMO,$7200/year,2500,30,,30,60,20
Bronze PPO,275,6000,40,8500,40,80,25
Platinum HMO,625,500,10,5000,15,35,10
CSVEOF

chown ga:ga /home/ga/Documents/insurance_plans_raw.csv
echo "✅ Created insurance_plans_raw.csv"

# Install odfpy if not present (for creating proper ODS)
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
# apt-get update -qq && apt-get install -y -qq python3-odf > /dev/null 2>&1 || pip3 install odfpy > /dev/null 2>&1
fi

# Create a proper starter ODS file with messy data and notes
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TableColumnProperties, TextProperties
from odf.number import NumberStyle, Number, Text as NumText, CurrencyStyle, CurrencySymbol

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet
table = Table(name="Insurance Comparison")
doc.spreadsheet.addElement(table)

# Helper to add a row of data
def add_row(values):
    row = TableRow()
    for val in values:
        cell = TableCell()
        if val is not None and val != "":
            cell.addElement(P(text=str(val)))
            if isinstance(val, (int, float)):
                cell.setAttrNS("urn:oasis:names:tc:opendocument:xmlns:office:1.0", "value-type", "float")
                cell.setAttrNS("urn:oasis:names:tc:opendocument:xmlns:office:1.0", "value", str(val))
        row.addElement(cell)
    table.addElement(row)

# Header row
add_row(["Plan Name", "Monthly Premium", "Deductible", "Co-insurance %", "Out-of-Pocket Max", 
         "PCP Visit", "Specialist Visit", "Generic Rx"])

# Plan data (with intentional messiness)
add_row(["Gold PPO", 450, 1000, 20, 6500, 25, 50, 15])
add_row(["Silver HMO", "$7200/year", 2500, 30, "", 30, 60, 20])  # Annual premium, missing OOP max
add_row(["Bronze PPO", 275, 6000, 40, 8500, 40, 80, 25])
add_row(["Platinum HMO", 625, 500, 10, 5000, 15, 35, 10])

# Add empty rows
for _ in range(2):
    add_row([""] * 8)

# Add notes section
add_row(["NOTES:"])
add_row(["- Plan B (Silver HMO) premium is $7200 per year (needs conversion to monthly)"])
add_row(["- Plan C (Bronze PPO) out-of-pocket max is $8500 (not shown above due to data entry error)"])
add_row(["- Create three scenarios: Minimal Use, Moderate Use, High Use"])

# Add empty rows for scenario section
for _ in range(2):
    add_row([""] * 8)

# Add scenario headers
add_row(["SCENARIO CALCULATIONS"])
add_row(["", "Minimal Use", "Moderate Use", "High Use"])
add_row(["Plan Name", "(2 PCP, 1 Specialist, $300 Rx)", "(4 PCP, 3 Specialist, $1500 Rx)", "(High medical costs)"])

# Add empty rows for scenario calculations
for _ in range(5):
    add_row([""] * 4)

# Save file
doc.save("/home/ga/Documents/insurance_comparison.ods")
print("✅ Created insurance_comparison.ods with messy data and notes")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/insurance_comparison.ods
sudo chmod 666 /home/ga/Documents/insurance_comparison.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/insurance_comparison.ods > /tmp/calc_insurance_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_insurance_task.log || true
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

# Ensure cursor is at A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Health Insurance Decision Rescue Task Setup Complete ==="
echo "📝 Task Overview:"
echo "  • Clean up messy insurance plan data"
echo "  • Convert annual premium to monthly (Plan B)"
echo "  • Fill missing Out-of-Pocket Max (Plan C: $8500)"
echo "  • Create 3 usage scenario models"
echo "  • Calculate total annual costs with formulas"
echo "  • Apply conditional formatting to highlight best options"
echo "  • Add decision support for different user needs"
echo ""
echo "💡 Key Challenges:"
echo "  • Data inconsistency (annual vs monthly premiums)"
echo "  • Missing data (find in notes section)"
echo "  • Complex formulas (premium + out-of-pocket costs)"
echo "  • Multi-scenario comparison"