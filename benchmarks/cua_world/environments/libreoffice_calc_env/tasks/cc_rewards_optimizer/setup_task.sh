#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Credit Card Rewards Optimization Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create Card Details CSV
cat > /tmp/card_details.csv << 'EOF'
Card_Name,Groceries,Gas,Dining,Travel,General
Chase Freedom,0.05,0.01,0.01,0.01,0.01
Discover,0.01,0.05,0.01,0.01,0.01
Amex Blue Preferred,0.06,0.03,0.01,0.01,0.01
Citi Double Cash,0.02,0.02,0.02,0.02,0.02
EOF

# Create Transactions CSV with realistic data and intentional issues
cat > /tmp/transactions.csv << 'EOF'
Date,Merchant,Amount,Card_Used,Category
2024-01-05,Whole Foods,87.23,Chase Freedom,General
2024-01-07,Shell Gas Station,42.00,Discover,
2024-01-08,Olive Garden,65.50,Chase Freedom,Dining
2024-01-10,United Airlines,320.00,Discover,Travel
2024-01-12,Safeway,112.45,Citi Double Cash,Groceries
2024-01-15,Chevron,38.75,Chase Freedom,Gas
2024-01-18,Starbucks,12.50,Amex Blue Preferred,
2024-01-20,Trader Joes,95.30,Discover,Groceries
2024-01-22,Delta Airlines,450.00,Chase Freedom,Travel
2024-01-25,BP Gas,44.20,Citi Double Cash,Gas
2024-01-27,Chipotle,28.75,Amex Blue Preferred,Dining
2024-01-30,Costco,156.80,Chase Freedom,General
2024-02-02,Southwest Airlines,280.00,Discover,Travel
2024-02-05,Kroger,78.90,Amex Blue Preferred,Groceries
2024-02-08,Panera Bread,23.40,Citi Double Cash,Dining
2024-02-10,Target,145.60,Chase Freedom,General
2024-02-12,Exxon,51.30,Discover,Gas
2024-02-15,Red Lobster,89.25,Amex Blue Preferred,Dining
2024-02-18,Albertsons,103.70,Citi Double Cash,
2024-02-20,American Airlines,395.00,Chase Freedom,Travel
2024-02-22,Subway,15.80,Discover,Dining
2024-02-25,Publix,88.40,Amex Blue Preferred,Groceries
2024-02-28,Walmart,167.90,Citi Double Cash,General
2024-03-02,Shell,46.85,Chase Freedom,Gas
2024-03-05,Outback Steakhouse,92.60,Discover,
2024-03-08,Sprouts,71.25,Amex Blue Preferred,Groceries
2024-03-10,JetBlue,310.00,Citi Double Cash,Travel
2024-03-12,Wendys,18.90,Chase Freedom,Dining
2024-03-15,Mobil,39.60,Discover,Gas
2024-03-18,Best Buy,234.50,Amex Blue Preferred,General
2024-03-20,Applebees,54.30,Citi Double Cash,Dining
2024-03-22,Harris Teeter,96.75,Chase Freedom,Groceries
2024-03-25,Texaco,42.90,Discover,Gas
2024-03-28,PF Changs,76.80,Amex Blue Preferred,
2024-03-30,Amazon Fresh,118.45,Citi Double Cash,Groceries
EOF

# Install odfpy if not present (needed to create ODS files)
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
# apt-get update -qq && apt-get install -y -qq python3-odf > /dev/null 2>&1
fi

# Create ODS file with multiple sheets using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
import csv

def add_text_cell(row, text):
    """Add a text cell to a row"""
    cell = TableCell()
    if text:
        cell.addElement(P(text=str(text)))
    row.addElement(cell)

def add_csv_to_sheet(doc, csv_path, sheet_name):
    """Read CSV and add as a sheet to the document"""
    table = Table(name=sheet_name)
    
    with open(csv_path, 'r') as f:
        reader = csv.reader(f)
        for csv_row in reader:
            table_row = TableRow()
            for cell_value in csv_row:
                add_text_cell(table_row, cell_value)
            table.addElement(table_row)
    
    doc.spreadsheet.addElement(table)

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add Transactions sheet
add_csv_to_sheet(doc, '/tmp/transactions.csv', 'Transactions')

# Add Card_Details sheet
add_csv_to_sheet(doc, '/tmp/card_details.csv', 'Card_Details')

# Add empty Analysis sheet
analysis_table = Table(name="Analysis")
# Add a few empty rows
for _ in range(20):
    row = TableRow()
    for _ in range(10):
        add_text_cell(row, "")
    analysis_table.addElement(row)
doc.spreadsheet.addElement(analysis_table)

# Save the file
doc.save("/home/ga/Documents/cc_rewards_analysis.ods")
print("Created ODS file with three sheets successfully")
PYEOF

# Clean up temp files
rm -f /tmp/transactions.csv /tmp/card_details.csv

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/cc_rewards_analysis.ods
sudo chmod 666 /home/ga/Documents/cc_rewards_analysis.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/cc_rewards_analysis.ods > /tmp/calc_rewards_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_rewards_task.log
    # Don't exit, continue
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit, continue
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

# Ensure cursor is at A1 of first sheet
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Credit Card Rewards Optimization Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Review Transactions sheet - fix blank/incorrect categories"
echo "  2. Add Optimal_Card column using lookup formulas"
echo "  3. Calculate Actual_Rewards, Optimal_Rewards, Opportunity_Cost"
echo "  4. Create summary analysis in Analysis sheet"
echo "  5. Build category recommendation table"
echo ""
echo "💡 Sheets available: Transactions, Card_Details, Analysis"
echo "💡 Categories: Groceries, Gas, Dining, Travel, General"