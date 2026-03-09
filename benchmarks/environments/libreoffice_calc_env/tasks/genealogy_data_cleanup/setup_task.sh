#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Genealogy Data Cleanup Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not already installed (for creating ODS files)
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
# apt-get update -qq && apt-get install -y -qq python3-odf
fi

# Create messy genealogy data ODS file
echo "Creating messy genealogy data file..."
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet
table = Table(name="Family Data")
doc.spreadsheet.addElement(table)

# Helper function to add cell
def add_cell(row, value):
    cell = TableCell()
    if value is not None:
        p = P(text=str(value))
        cell.addElement(p)
    row.addElement(cell)

# Header row
header_row = TableRow()
headers = ["ID", "Given Name", "Surname", "Birth Date", "Birth Place", "Death Date", "Death Place", "Parents", "Notes", "Source"]
for h in headers:
    add_cell(header_row, h)
table.addElement(header_row)

# Messy genealogy data (~45 entries, representing ~30 unique people)
# Includes duplicates, various date formats, logical errors, missing data
data = [
    # Smith family
    [1, "John", "Smith", "1850", "Boston, MA", "1920-03-15", "Boston, MA", "", "Patriarch", "Census 1900"],
    [2, "John", "Smith", "circa 1850", "Boston", "March 15, 1920", "Boston, MA", "", "Same person as #1", "Death cert"],
    [3, "Mary", "Smith", "1852-06-20", "Boston, MA", "1935-11-02", "Boston, MA", "John Smith & Jane Doe", "", "Birth record"],
    [4, "Mary Elizabeth", "Smith", "June 1852", "Boston", "1935-11-02", "", "John Smith", "Daughter of John", "Family Bible"],
    [5, "Mary E.", "Smith", "1852", "Boston, MA", "Nov 2, 1935", "Boston, MA", "", "", "Obituary"],
    
    # Johnson family
    [6, "Robert", "Johnson", "1845-12-01", "New York, NY", "1925-05-20", "New York, NY", "", "", "Census"],
    [7, "Sarah", "Johnson", "1848-03-15", "New York, NY", "1930-08-10", "New York, NY", "", "Wife of Robert", "Marriage record"],
    [8, "Sarah Ann", "Johnson", "March 1848", "New York", "1930-08-10", "", "Thomas Wilson & Mary Wilson", "", "Birth cert"],
    [9, "William", "Johnson", "1870-07-04", "New York, NY", "1945-12-25", "New York, NY", "Robert Johnson & Sarah Johnson", "", "Census"],
    [10, "William R.", "Johnson", "July 4, 1870", "New York", "1945", "", "Robert & Sarah Johnson", "Son", "Family records"],
    
    # Brown family with errors
    [11, "James", "Brown", "1880-01-10", "Chicago, IL", "1875-06-15", "Chicago, IL", "", "ERROR: Death before birth!", "Needs verification"],
    [12, "James", "Brown", "1880", "Chicago", "1960-06-15", "Chicago, IL", "", "Corrected dates", "Death cert"],
    [13, "Emma", "Brown", "1882-05-20", "Chicago, IL", "2010-03-30", "Chicago, IL", "", "Lived to 128 - ERROR!", "Family claim"],
    [14, "Emma", "Brown", "1882", "Chicago", "1975-03-30", "", "James Brown & Lucy Brown", "", "Corrected"],
    
    # Davis family
    [15, "Thomas", "Davis", "ca. 1835", "Philadelphia, PA", "1900", "Philadelphia, PA", "", "", "Estimate"],
    [16, "Thomas", "Davis", "about 1835", "Philadelphia", "circa 1900", "", "", "Uncertain dates", "Family tradition"],
    [17, "Margaret", "Davis", "1840-09-12", "Philadelphia, PA", "1920-04-05", "Philadelphia, PA", "", "Wife of Thomas", "Census"],
    [18, "Charles", "Davis", "1865-11-23", "Philadelphia, PA", "1940-02-14", "Philadelphia, PA", "Thomas Davis & Margaret Davis", "", "Birth record"],
    [19, "Charles T.", "Davis", "Nov 23, 1865", "Philadelphia", "1940", "", "Thomas & Margaret", "", "Obituary"],
    
    # Wilson family
    [20, "Henry", "Wilson", "1855-03-30", "Baltimore, MD", "1935-07-18", "Baltimore, MD", "", "", "Census"],
    [21, "Elizabeth", "Wilson", "1858-12-05", "Baltimore, MD", "", "", "", "Still living?", "Unknown"],
    [22, "Elizabeth Jane", "Wilson", "December 1858", "Baltimore", "", "", "David Wilson & Ann Wilson", "No death record found", "Birth cert"],
    [23, "George", "Wilson", "1880-06-15", "Baltimore, MD", "1955-09-22", "Baltimore, MD", "Henry Wilson & Elizabeth Wilson", "", "Death cert"],
    
    # Miller family with parent age error
    [24, "Edward", "Miller", "1900-04-10", "Detroit, MI", "1975-11-30", "Detroit, MI", "", "", "Birth cert"],
    [25, "Alice", "Miller", "1908-08-05", "Detroit, MI", "1995-03-15", "Detroit, MI", "Edward Miller & Jane Miller", "ERROR: Father only 8!", "Needs check"],
    [26, "Alice Marie", "Miller", "1920-08-05", "Detroit", "1995", "", "Edward & Jane Miller", "Corrected birth year", "Family Bible"],
    
    # Anderson family
    [27, "Oscar", "Anderson", "1865", "Minneapolis, MN", "1945", "Minneapolis, MN", "", "", "Estimate"],
    [28, "Oscar", "Anderson", "circa 1865", "Minneapolis", "ca. 1945", "", "", "", "Uncertain"],
    [29, "Sophia", "Anderson", "1868-01-20", "Minneapolis, MN", "1950-05-10", "Minneapolis, MN", "", "", "Census"],
    [30, "Sophia M.", "Anderson", "Jan 1868", "Minneapolis", "1950", "", "", "Wife of Oscar", "Death index"],
    
    # Taylor family
    [31, "Frank", "Taylor", "1875-09-08", "St. Louis, MO", "1960-12-20", "St. Louis, MO", "", "", "Birth record"],
    [32, "Rose", "Taylor", "1878-03-25", "St. Louis, MO", "1965-08-14", "St. Louis, MO", "", "Wife of Frank", "Marriage cert"],
    [33, "Frank Jr.", "Taylor", "1900-05-15", "St. Louis, MO", "1985-02-28", "St. Louis, MO", "Frank Taylor & Rose Taylor", "", "Census"],
    
    # Martin family
    [34, "Arthur", "Martin", "1890-11-11", "Boston, MA", "1970-06-30", "Boston, MA", "", "", "Birth cert"],
    [35, "Arthur J.", "Martin", "Nov 11, 1890", "Boston", "1970", "", "", "Same as #34", "Death cert"],
    [36, "Grace", "Martin", "1892-07-04", "Boston, MA", "1975-09-20", "Boston, MA", "", "Wife of Arthur", "Marriage record"],
    
    # Clark family
    [37, "Walter", "Clark", "1885", "Cleveland, OH", "1960", "Cleveland, OH", "", "", "Estimate"],
    [38, "Dorothy", "Clark", "1888-02-14", "Cleveland, OH", "1972-11-05", "Cleveland, OH", "", "", "Birth record"],
    [39, "Walter Jr.", "Clark", "1910-08-22", "Cleveland, OH", "1995-04-10", "Cleveland, OH", "Walter Clark & Dorothy Clark", "", "Census"],
    
    # White family
    [40, "Samuel", "White", "1870-05-30", "Denver, CO", "1950-10-12", "Denver, CO", "", "", "Birth cert"],
    [41, "Samuel", "White", "May 30, 1870", "Denver", "1950", "", "", "", "Death index"],
    [42, "Helen", "White", "1873-09-18", "Denver, CO", "1955-12-08", "Denver, CO", "", "Wife of Samuel", "Census"],
    
    # Additional singles to reach ~45 entries
    [43, "Unknown", "Person", "", "", "", "", "", "Incomplete record", "Mystery"],
    [44, "Jane", "Doe", "1860", "Unknown", "", "", "", "Lost track", "Family mention"],
    [45, "Thomas", "Unknown", "1855-01-01", "", "1855-01-01", "", "", "ERROR: Born and died same day infant?", "Suspicious"],
]

for row_data in data:
    row = TableRow()
    for value in row_data:
        add_cell(row, value)
    table.addElement(row)

# Save the file
output_path = "/home/ga/Documents/family_data_raw.ods"
doc.save(output_path)
print(f"Created messy genealogy data: {output_path}")
print(f"Total entries: {len(data)} (representing ~30 unique people)")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/family_data_raw.ods
sudo chmod 666 /home/ga/Documents/family_data_raw.ods

echo "✅ Created family_data_raw.ods with ~45 messy entries"

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/family_data_raw.ods > /tmp/calc_genealogy.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_genealogy.log || true
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

echo "=== Genealogy Data Cleanup Task Setup Complete ==="
echo "📊 Data loaded: ~45 messy entries representing ~30 unique people"
echo ""
echo "📝 Task Instructions:"
echo "  1. Standardize date formats to YYYY-MM-DD (handle 'circa', 'ca.', partial dates)"
echo "  2. Identify and consolidate duplicate entries (same person, different name variations)"
echo "  3. Add 'Age at Death' column with formulas"
echo "  4. Add 'Data Issues' column to flag logical errors (death before birth, age >120, etc.)"
echo "  5. Apply conditional formatting to highlight problematic rows"
echo "  6. Sort by Surname, then Birth Year"
echo "  7. Save as genealogy_clean.ods"
echo ""
echo "⚠️  Known issues in data:"
echo "  - Multiple date formats: 'circa 1850', '3/15/1850', 'March 1850', '1850'"
echo "  - Duplicates: John Smith appears 2x, Mary Smith 3x, etc."
echo "  - Death before birth: James Brown (row 11)"
echo "  - Impossible age: Emma Brown lived to 128 (row 13)"
echo "  - Parent age error: Alice Miller, father only 8 years old (row 25)"