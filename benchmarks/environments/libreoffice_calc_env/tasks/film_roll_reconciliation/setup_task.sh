#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Film Roll Reconciliation Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not already installed
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
# apt-get update -qq && apt-get install -y -qq python3-odf
fi

# Create the multi-sheet ODS file using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TableColumnProperties, TextProperties
from odf.number import NumberStyle, Number, Text as NumberText, CurrencySymbol

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

def add_cell(row, value, value_type='string'):
    """Helper to add a cell with value"""
    cell = TableCell(valuetype=value_type)
    if value_type == 'string':
        cell.addElement(P(text=str(value)))
    elif value_type == 'float':
        cell.setAttribute('value', str(value))
        cell.addElement(P(text=str(value)))
    row.addElement(cell)
    return cell

def add_header_row(table, headers):
    """Add a header row"""
    row = TableRow()
    for header in headers:
        add_cell(row, header, 'string')
    table.addElement(row)

def add_data_row(table, values, types=None):
    """Add a data row"""
    if types is None:
        types = ['string'] * len(values)
    row = TableRow()
    for value, vtype in zip(values, types):
        add_cell(row, value, vtype)
    table.addElement(row)

# Sheet 1: Shooting Notes
notes_table = Table(name="Shooting Notes")
add_header_row(notes_table, ["Frame Range", "Description", "Location", "Camera", "Date", "Priority"])
add_data_row(notes_table, ["1-8", "Sunrise test shots", "Beach", "Nikon FM", "2024-07-15", "Test"])
add_data_row(notes_table, ["9-15", "Family beach photos", "Beach", "Nikon FM", "2024-07-15", "Priority"])
add_data_row(notes_table, ["16-22", "Tide pools exploration", "Beach", "Nikon FM", "2024-07-16", "Test"])
add_data_row(notes_table, ["23-28", "Downtown walking", "City Center", "Olympus", "2024-07-17", "Test"])
add_data_row(notes_table, ["29-38", "Harbor at sunset", "Harbor", "Olympus", "2024-07-17", "Priority"])
add_data_row(notes_table, ["1-12", "Mountain trail", "Mt. Ridge", "Nikon FM", "2024-07-18", "Test"])
add_data_row(notes_table, ["13-24", "Wildflowers closeup", "Mt. Ridge", "Nikon FM", "2024-07-18", "Priority"])
add_data_row(notes_table, ["25-32", "Family group shots", "Mt. Ridge", "Nikon FM", "2024-07-18", "Priority"])
doc.spreadsheet.addElement(notes_table)

# Sheet 2: Lab Rolls
lab_table = Table(name="Lab Rolls")
add_header_row(lab_table, ["Lab Roll ID", "Frame Count", "Development Cost", "Return Date", "Film Type"])
add_data_row(lab_table, ["R2847-A", "22", "$14.50", "2024-07-25", "Portra 400"], 
             ['string', 'float', 'string', 'string', 'string'])
add_data_row(lab_table, ["R2847-B", "38", "$14.50", "2024-07-25", "Portra 400"],
             ['string', 'float', 'string', 'string', 'string'])
add_data_row(lab_table, ["R2847-C", "32", "$14.50", "2024-07-25", "Portra 400"],
             ['string', 'float', 'string', 'string', 'string'])
doc.spreadsheet.addElement(lab_table)

# Sheet 3: Roll Specs
specs_table = Table(name="Roll Specs")
add_header_row(specs_table, ["Film Type", "Max Frames", "Dev Cost", "Scan Cost per Frame"])
add_data_row(specs_table, ["Portra 400", "36", "$14.50", "$0.50"],
             ['string', 'float', 'string', 'string'])
add_data_row(specs_table, ["Ektar 100", "36", "$16.00", "$0.50"],
             ['string', 'float', 'string', 'string'])
add_data_row(specs_table, ["HP5 Plus", "36", "$12.00", "$0.40"],
             ['string', 'float', 'string', 'string'])
doc.spreadsheet.addElement(specs_table)

# Save the file
output_path = "/home/ga/Documents/film_rolls.ods"
doc.save(output_path)
print(f"Created multi-sheet ODS file: {output_path}")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/film_rolls.ods
sudo chmod 666 /home/ga/Documents/film_rolls.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/film_rolls.ods > /tmp/calc_film_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_film_task.log || true
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

# Navigate to first sheet
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Film Roll Reconciliation Task Setup Complete ==="
echo "📸 Task: Reconcile film shooting notes with lab roll returns"
echo "📋 Provided sheets:"
echo "   - Shooting Notes: Photographer's original notes"
echo "   - Lab Rolls: Lab return data (note: different IDs!)"
echo "   - Roll Specs: Film type reference data"
echo ""
echo "🎯 Your goal:"
echo "   1. Create a new 'Reconciliation' sheet"
echo "   2. Match lab roll IDs to original shooting notes"
echo "   3. Flag rolls with >36 frames (one roll has 38!)"
echo "   4. Count priority shots per roll"
echo "   5. Calculate scan priority scores"
echo "   6. Calculate cost per frame"
echo "   7. Apply conditional formatting"