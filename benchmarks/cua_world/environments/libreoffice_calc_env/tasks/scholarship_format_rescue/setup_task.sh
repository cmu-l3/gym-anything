#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Scholarship Format Rescue Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create requirements specification document
cat > /home/ga/Documents/scholarship_requirements.txt << 'REQEOF'
SCHOLARSHIP FINANCIAL DATA SUBMISSION FORMAT
=============================================

DEADLINE: 48 hours
FILE NAME: financial_data_submission.csv
FORMAT: CSV (UTF-8, comma-delimited, no quotes around text unless needed)
ACADEMIC YEAR: 2023-2024 (Aug 1, 2023 - Jul 31, 2024)

REQUIRED COLUMNS (in exact order, case-sensitive):
===================================================
1. Transaction_ID    (text, unique identifier)
2. Date              (text, format: YYYY-MM-DD)
3. Category          (text, must match taxonomy below)
4. Description       (text, max 100 characters)
5. Amount            (number, 2 decimal places, negative as -1234.56 not (1234.56))
6. Monthly_Amount    (number, calculated as Amount/12, 2 decimal places)
7. Semester_Total    (number, calculated as Monthly_Amount*4, 2 decimal places)
8. Needs_Based       (text, "Yes" or "No" - Yes if Source is Grant or Scholarship)
9. Source            (text, one of: Loan, Grant, Scholarship, Work-Study, Personal)

CATEGORY TAXONOMY (exact spelling required):
============================================
- Tuition
- Housing
- Educational Materials
- Transportation
- Healthcare
- Miscellaneous

SOURCE VALUES (exact spelling):
===============================
- Loan
- Grant
- Scholarship
- Work-Study
- Personal

VALIDATION RULES:
=================
- No empty fields in required columns
- All dates must be within Aug 1, 2023 - Jul 31, 2024
- All Transaction_IDs must be unique
- All amounts must use period (.) as decimal separator
- Negative values must use minus sign (-), not parentheses
- Calculations must be accurate (Monthly_Amount = Amount/12, Semester_Total = Monthly_Amount*4)

FORMATTING REQUIREMENTS:
========================
- CSV file with UTF-8 encoding
- Comma as field delimiter
- No cell background colors or formatting
- Numbers must be actual numbers (not text that looks like numbers)
- Dates must be text in YYYY-MM-DD format (not date serial numbers)

PORTAL WILL AUTO-REJECT IF:
============================
- Wrong filename
- Wrong column count or order
- Misspelled column names
- Invalid category or source values
- Date not in YYYY-MM-DD format
- Empty required fields
- Incorrect calculations
REQEOF

sudo chown ga:ga /home/ga/Documents/scholarship_requirements.txt

echo "✅ Created requirements document"

# Install Python ODF library if not present (for creating ODS files)
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing python3-odf..."
# sudo apt-get update -qq && sudo apt-get install -y -qq python3-odf
fi

# Create messy source data file with intentional format issues
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P

# Create spreadsheet
doc = OpenDocumentSpreadsheet()
table = Table(name="Financial Aid Export")

# Helper function to create cell with value
def make_cell(value, value_type='string'):
    cell = TableCell()
    if value_type == 'string':
        cell.setAttrNS(None, 'office:value-type', 'string')
    elif value_type == 'float':
        cell.setAttrNS(None, 'office:value-type', 'float')
        cell.setAttrNS(None, 'office:value', str(value))
    p = P()
    p.addText(str(value))
    cell.addElement(p)
    return cell

# Header row (with wrong names and order, plus extra columns)
header_row = TableRow()
headers = ['Trans_ID', 'Date_Received', 'Expense_Type', 'Details', 'Total_Amount', 
           'Funding_Source', 'Internal_Code', 'Process_Date']
for h in headers:
    header_row.addElement(make_cell(h))
table.addElement(header_row)

# Data rows with intentional issues
data = [
    # Transaction_ID, Date (messy format), Category (wrong names), Description, Amount (some as text), Source, Internal_Code, Process_Date
    ['FA-2024-001', '09/15/2023', 'Books', 'Textbooks for Fall 2023', '850.00', 'Scholarship', 'INT-001', '2023-09-01'],
    ['FA-2024-002', '15-Sep-23', 'Room & Board', 'Campus Housing - Fall', '(1200.00)', 'Loan', 'INT-002', '2023-09-01'],
    ['FA-2024-003', 'September 20, 2023', 'Tuition', 'Fall Semester Tuition', '12500', 'Grant', 'INT-003', '2023-09-05'],
    ['FA-2024-004', '10/01/2023', 'Personal Expenses', 'Healthcare insurance', '450.75', 'Personal', 'INT-004', '2023-10-01'],
    ['FA-2024-005', '01-Oct-23', 'Parking Pass', 'Campus parking Fall/Spring', '180.00', 'Work-Study', 'INT-005', '2023-10-01'],
    ['FA-2024-006', 'October 15, 2023', 'Books', 'Lab materials', '(95.50)', 'Grant', 'INT-006', '2023-10-10'],
    ['FA-2024-007', '01/15/2024', 'Room & Board', 'Campus Housing - Spring', '1200.00', 'Loan', 'INT-007', '2024-01-05'],
    ['FA-2024-008', '15-Jan-24', 'Tuition', 'Spring Semester Tuition', '12500.00', 'Scholarship', 'INT-008', '2024-01-05'],
    ['FA-2024-009', 'January 20, 2024', 'Meal Plan', 'Spring Semester Meals', "'980.00'", 'Loan', 'INT-009', '2024-01-10'],
    ['FA-2024-010', '02/01/2024', 'Transportation', 'Public transit pass', '120.00', 'Personal', 'INT-010', '2024-02-01'],
    ['FA-2024-011', '01-Feb-24', 'Books', 'Spring semester textbooks', '675.25', 'Grant', 'INT-011', '2024-02-01'],
    ['FA-2024-012', 'February 15, 2024', 'Medical', 'Student health fee', '225.00', 'Grant', 'INT-012', '2024-02-10'],
    ['FA-2024-013', '03/01/2024', 'Books', 'Research materials', '(45.99)', 'Work-Study', 'INT-013', '2024-03-01'],
    ['FA-2024-014', '15-Mar-24', 'Personal Expenses', 'Misc supplies', '78.50', 'Personal', 'INT-014', '2024-03-15'],
    ['FA-2024-015', 'March 20, 2024', 'Transportation', 'Gas for commute', '150.00', 'Work-Study', 'INT-015', '2024-03-20'],
]

for row_data in data:
    row = TableRow()
    for i, val in enumerate(row_data):
        # Make amounts with apostrophes look like text
        if isinstance(val, str) and val.startswith("'"):
            row.addElement(make_cell(val))
        else:
            row.addElement(make_cell(val))
    table.addElement(row)

doc.spreadsheet.addElement(table)
doc.save("/home/ga/Documents/financial_aid_export.ods")
print("✅ Created messy source data file with format issues")
PYEOF

# Set permissions
sudo chown ga:ga /home/ga/Documents/financial_aid_export.ods
sudo chmod 666 /home/ga/Documents/financial_aid_export.ods

echo "✅ Created financial_aid_export.ods with intentional format issues:"
echo "   - Inconsistent date formats (MM/DD/YYYY, DD-Mon-YY, Month DD, YYYY)"
echo "   - Text-formatted numbers (leading apostrophes)"
echo "   - Negative numbers as (1234) instead of -1234"
echo "   - Wrong category names (Books, Room & Board, etc.)"
echo "   - Missing required columns (Monthly_Amount, Semester_Total, Needs_Based)"
echo "   - Extra columns (Internal_Code, Process_Date)"
echo "   - Wrong column names and order"

# Launch LibreOffice Calc with the source file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/financial_aid_export.ods > /tmp/calc_scholarship_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "WARNING: LibreOffice may not have started"
    cat /tmp/calc_scholarship_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "WARNING: LibreOffice Calc window may not have appeared"
fi

# Click on center of screen to select desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Calc window and maximize
echo "Focusing Calc window..."
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
        
        # Move cursor to A1
        safe_xdotool ga :1 key ctrl+Home
        sleep 0.3
    fi
fi

echo ""
echo "=== Scholarship Format Rescue Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "   A student must transform messy financial aid data into the exact format"
echo "   required by a scholarship application portal. The deadline is in 48 hours!"
echo ""
echo "📄 Files Available:"
echo "   - /home/ga/Documents/financial_aid_export.ods (source data - MESSY)"
echo "   - /home/ga/Documents/scholarship_requirements.txt (format specification)"
echo ""
echo "🎯 GOAL:"
echo "   Transform the data and export as: financial_data_submission.csv"
echo ""
echo "⚠️  CRITICAL REQUIREMENTS:"
echo "   - Exact column names (case-sensitive): Transaction_ID, Date, Category, etc."
echo "   - Dates in YYYY-MM-DD format (currently mixed formats)"
echo "   - Numbers as actual numbers (fix text-formatted values)"
echo "   - Fix negative numbers: (1234) → -1234"
echo "   - Map categories to taxonomy (Books → Educational Materials, etc.)"
echo "   - Calculate: Monthly_Amount = Amount/12"
echo "   - Calculate: Semester_Total = Monthly_Amount*4"
echo "   - Calculate: Needs_Based = 'Yes' if Source is Grant or Scholarship"
echo "   - Remove extra columns: Internal_Code, Process_Date"
echo "   - Reorder columns to match specification"
echo ""
echo "💡 TIP: Open scholarship_requirements.txt to see exact format specifications"
echo ""