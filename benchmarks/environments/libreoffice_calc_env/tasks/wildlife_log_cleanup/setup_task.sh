#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Wildlife Log Cleanup Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not already installed
echo "Ensuring odfpy is installed..."
pip3 install --quiet odfpy || true

# Create the wildlife observation spreadsheet with two sheets using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# ===== Sheet 1: Observations (messy raw data) =====
observations_table = Table(name="Observations")

# Header row
header_row = TableRow()
headers = ["Date", "Species", "Count", "Time_of_Day", "Notes"]
for header_text in headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header_text))
    header_row.addElement(cell)
observations_table.addElement(header_row)

# Raw observation data (messy)
raw_data = [
    ["5/12/23", "cardinal", "2", "morning", "male and female at feeder"],
    ["05-13-2023", "chickadee", "4", "morning", ""],
    ["May 14 2023", "blue jay", "1", "afternoon", "noisy!"],
    ["5/15/23", "rabbit", "1", "evening", "eastern cottontail"],
    ["5/16/23", "deer", "3", "dawn", "doe with two fawns"],
    ["5/17/23", "hawk", "1", "morning", "red-tailed?"],
    ["5/18/23", "cardinal", "3", "afternoon", ""],
    ["5/19/23", "squirrel", "12", "all day", "gray squirrels everywhere"],
    ["5/20/23", "chickadee", "5", "morning", "black-capped"],
    ["5/21/23", "robin", "2", "morning", "american robin"],
    ["5/22/23", "deer", "50", "evening", "CHECK THIS - seems wrong"],
    ["5/23/23", "cardinal", "2", "morning", ""],
    ["May 24 2023", "unknown bird", "1", "afternoon", "small brown bird"],
    ["5/25/23", "chipmunk", "1", "morning", "eastern chipmunk"],
    ["5/26/23", "blue jay", "2", "afternoon", ""],
    ["05-27-2023", "rabbit", "2", "evening", ""],
    ["5/28/23", "cardinal", "4", "morning", ""],
    ["May 29 2023", "hawk", "1", "afternoon", "soaring overhead"],
    ["5/30/23", "squirrel", "8", "all day", ""],
    ["5/31/23", "chickadee", "6", "morning", ""],
]

for row_data in raw_data:
    row = TableRow()
    for cell_value in row_data:
        cell = TableCell(valuetype="string")
        cell.addElement(P(text=str(cell_value)))
        row.addElement(cell)
    observations_table.addElement(row)

doc.spreadsheet.addElement(observations_table)

# ===== Sheet 2: Species_Reference (lookup table) =====
reference_table = Table(name="Species_Reference")

# Header row
ref_header_row = TableRow()
ref_headers = ["Common_Name", "Standardized_Name", "Scientific_Name", "Max_Expected_Count", "Rarity"]
for header_text in ref_headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header_text))
    ref_header_row.addElement(cell)
reference_table.addElement(ref_header_row)

# Reference data
reference_data = [
    ["cardinal", "Northern Cardinal", "Cardinalis cardinalis", "5", "Common"],
    ["chickadee", "Black-capped Chickadee", "Poecile atricapillus", "8", "Common"],
    ["blue jay", "Blue Jay", "Cyanocitta cristata", "4", "Common"],
    ["rabbit", "Eastern Cottontail", "Sylvilagus floridanus", "3", "Uncommon"],
    ["deer", "White-tailed Deer", "Odocoileus virginianus", "5", "Uncommon"],
    ["hawk", "Red-tailed Hawk", "Buteo jamaicensis", "2", "Uncommon"],
    ["squirrel", "Eastern Gray Squirrel", "Sciurus carolinensis", "10", "Common"],
    ["robin", "American Robin", "Turdus migratorius", "6", "Common"],
    ["chipmunk", "Eastern Chipmunk", "Tamias striatus", "3", "Common"],
    ["mourning dove", "Mourning Dove", "Zenaida macroura", "8", "Common"],
]

for row_data in reference_data:
    row = TableRow()
    for i, cell_value in enumerate(row_data):
        if i == 3:  # Max_Expected_Count is a number
            cell = TableCell(valuetype="float", value=cell_value)
            cell.addElement(P(text=str(cell_value)))
        else:
            cell = TableCell(valuetype="string")
            cell.addElement(P(text=str(cell_value)))
        row.addElement(cell)
    reference_table.addElement(row)

doc.spreadsheet.addElement(reference_table)

# Save the file
doc.save("/home/ga/Documents/wildlife_observations.ods")
print("✅ Created wildlife_observations.ods with two sheets")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/wildlife_observations.ods
sudo chmod 666 /home/ga/Documents/wildlife_observations.ods

# Verify file was created
if [ -f "/home/ga/Documents/wildlife_observations.ods" ]; then
    echo "✅ Wildlife observation file created successfully"
    ls -lh /home/ga/Documents/wildlife_observations.ods
else
    echo "❌ ERROR: Failed to create wildlife observation file"
    exit 1
fi

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc with wildlife observations..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/wildlife_observations.ods > /tmp/calc_wildlife_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_wildlife_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
fi

# Click on center of the screen to select current desktop (should be done in all tasks)
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

# Ensure cursor is at A1 of Observations sheet
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Wildlife Log Cleanup Task Setup Complete ==="
echo "📝 Task Instructions:"
echo "  Sheet 1 (Observations): Messy wildlife observation data"
echo "  Sheet 2 (Species_Reference): Lookup table with standardized names"
echo ""
echo "  Your job:"
echo "  1. Add helper columns: Standard_Species, Standard_Date, Plausibility_Flag"
echo "  2. Use VLOOKUP to standardize species names from reference table"
echo "  3. Convert dates to uniform format (YYYY-MM-DD)"
echo "  4. Flag entries where Count > Max_Expected_Count"
echo "  5. Preserve all original data"
echo ""
echo "  💡 Hint: =VLOOKUP(B2, Species_Reference.\$A\$2:\$D\$20, 2, FALSE)"