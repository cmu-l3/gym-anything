#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Legacy POS Rescue Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create messy CSV file with realistic data problems
cat > /home/ga/Documents/old_pos_export.csv << 'CSVEOF'
CustomerName,PurchaseDate,Amount,PaymentMethod
John Smith,01/15/2021,$45.99,Credit
JOHN SMITH,03/22/2021,67.50 USD,Cash
J. Smith,2021-05-10,$23.75,Credit
Smith John,07/04/2021,$145.00,Credit
Jane Doe,02-14-2021,$89.99,Debit
jane doe,04/30/2021,$34.50,Cash
JANE DOE,2021-06-15,56.00,Credit
Sarah Johnson,2021-01-20,$125.50,Credit
Sarah Johnson,03-10-2021,78.25 USD,Cash
S. Johnson,2021-04-05,$42.00,Debit
Mike Davis,05/12/2021,$234.99,Credit
MIKE DAVIS,2021-07-08,89.50,Cash
M. Davis,08-22-2021,$156.75,Credit
Davis Mike,2021-09-14,67.00,Debit
Emily Wilson,2021-02-18,$98.50,Credit
Emily Wilson,04-25-2021,145.00,Credit
E. Wilson,2021-06-30,$78.25,Cash
Robert Brown,03/15/2021,$167.50,Credit
robert brown,2021-05-20,234.00,Debit
R. Brown,07-12-2021,$89.99,Credit
Brown Robert,2021-08-28,123.50,Cash
Lisa Anderson,2021-01-25,$76.50,Credit
LISA ANDERSON,03-18-2021,98.75,Cash
L. Anderson,2021-05-22,$145.00,Credit
Anderson Lisa,07-30-2021,67.25,Debit
Tom Martinez,04/10/2021,$189.99,Credit
Tom Martinez,2021-06-15,234.50,Credit
T. Martinez,08-20-2021,$156.75,Cash
Jennifer Taylor,2021-02-28,$98.25,Debit
JENNIFER TAYLOR,04-12-2021,145.50,Credit
J. Taylor,2021-06-25,$78.00,Cash
Taylor Jennifer,08-15-2021,234.75,Credit
David Miller,03/22/2021,$167.99,Credit
david miller,2021-05-18,89.50,Debit
D. Miller,07-25-2021,$234.00,Credit
Amanda Garcia,2021-01-30,$123.50,Cash
Amanda Garcia,04-05-2021,178.25,Credit
A. Garcia,2021-06-20,$89.99,Debit
Christopher Lee,05/08/2021,$245.75,Credit
CHRISTOPHER LEE,2021-07-15,167.50,Cash
C. Lee,09-10-2021,$98.25,Credit
Jessica White,2021-02-12,$134.99,Debit
Jessica White,04-28-2021,189.50,Credit
J. White,2021-07-05,$76.25,Cash
Matthew Harris,03/25/2021,$201.50,Credit
matthew harris,2021-06-08,145.75,Debit
M. Harris,08-18-2021,$234.00,Credit
Ashley Clark,2021-01-28,$89.99,Cash
ASHLEY CLARK,04-15-2021,156.50,Credit
A. Clark,2021-07-22,$98.75,Debit
Daniel Lewis,05/15/2021,$178.25,Credit
Daniel Lewis,2021-07-28,234.50,Credit
D. Lewis,09-12-2021,$145.75,Cash
Melissa Walker,2021-02-20,$123.50,Debit
melissa walker,04-22-2021,98.25,Credit
M. Walker,2021-07-10,$167.50,Cash
James Hall,03/18/2021,$234.75,Credit
JAMES HALL,2021-06-05,189.50,Debit
J. Hall,08-25-2021,$156.25,Credit
Nicole Young,2021-01-22,$98.50,Cash
Nicole Young,04-18-2021,145.75,Credit
N. Young,2021-07-15,$78.25,Debit
Kevin King,05/20/2021,$201.99,Credit
kevin king,2021-07-25,167.50,Cash
K. King,09-15-2021,$234.75,Credit
Rachel Scott,2021-02-25,$134.50,Debit
RACHEL SCOTT,04-30-2021,189.25,Credit
R. Scott,2021-07-20,$98.75,Cash
Brian Green,03/28/2021,$178.50,Credit
Brian Green,2021-06-12,234.75,Debit
B. Green,08-22-2021,$145.25,Credit
Stephanie Adams,2021-01-15,$89.99,Cash
stephanie adams,04-08-2021,156.50,Credit
S. Adams,2021-07-18,$98.25,Debit
Ryan Baker,05/25/2021,$223.75,Credit
Ryan Baker,2021-08-05,189.50,Credit
R. Baker,09-20-2021,$167.25,Cash
Laura Nelson,2021-02-18,$98.50,Debit
LAURA NELSON,04-25-2021,145.75,Credit
L. Nelson,2021-07-28,$78.99,Cash
Justin Carter,03/30-2021,$201.50,Credit
justin carter,2021-06-18,167.25,Debit
J. Carter,08-28-2021,$234.75,Credit
Megan Mitchell,2021-01-20,$134.99,Cash
Megan Mitchell,04-12-2021,178.50,Credit
M. Mitchell,2021-07-25,$89.25,Debit
Brandon Perez,05/28/2021,$245.75,Credit
BRANDON PEREZ,2021-08-10,198.50,Cash
B. Perez,09-25-2021,$156.25,Credit
Amber Roberts,2021-02-22,$98.75,Debit
Amber Roberts,04-28-2021,145.50,Credit
A. Roberts,2021-07-30,$234.25,Cash
Eric Turner,03/12/2021,$189.99,Credit
eric turner,2021-06-20,167.75,Debit
E. Turner,08-30-2021,$234.50,Credit
Kimberly Phillips,2021-01-18,$123.50,Cash
KIMBERLY PHILLIPS,04-15-2021,189.25,Credit
K. Phillips,2021-07-22,$98.50,Debit
Andrew Campbell,05/30/2021,$256.75,Credit
Andrew Campbell,2021-08-12,201.50,Credit
A. Campbell,09-28-2021,$178.25,Cash
Christina Parker,2021-02-15,$134.99,Debit
christina parker,04-20-2021,167.50,Credit
C. Parker,2021-07-25,$89.75,Cash
Tyler Evans,03/20/2021,$198.50,Credit
Tyler Evans,2021-06-25,234.25,Debit
T. Evans,08-20-2021,$156.75,Credit
Samantha Edwards,2021-01-28,$98.99,Cash
SAMANTHA EDWARDS,04-18-2021,145.50,Credit
S. Edwards,2021-07-28,$234.25,Debit
Gregory Collins,05/22/2021,$223.75,Credit
gregory collins,2021-08-08,189.50,Cash
G. Collins,09-22-2021,$167.25,Credit
Rebecca Stewart,2021-02-20,$123.50,Debit
Rebecca Stewart,04-25-2021,178.75,Credit
R. Stewart,2021-07-30,$98.25,Cash
Patrick Sanchez,03/25/2021,$201.99,Credit
PATRICK SANCHEZ,2021-06-28,167.50,Debit
P. Sanchez,08-25-2021,$245.75,Credit
Katherine Morris,2021-01-22,$134.50,Cash
katherine morris,04-22-2021,189.25,Credit
K. Morris,2021-07-25,$98.75,Debit
Aaron Rogers,05/18/2021,$234.75,Credit
Aaron Rogers,2021-08-15,198.50,Credit
A. Rogers,09-30-2021,$156.25,Cash
Victoria Reed,2021-02-28,$98.99,Debit
VICTORIA REED,04-30-2021,145.75,Credit
V. Reed,2021-08-05,$234.50,Cash
Nathan Cook,03/15/2021,$189.50,Credit
nathan cook,2021-06-22,167.25,Debit
N. Cook,08-28-2021,$223.75,Credit
Heather Morgan,2021-01-25,$123.99,Cash
Heather Morgan,04-28-2021,178.50,Credit
H. Morgan,2021-08-10,$89.25,Debit
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/old_pos_export.csv
sudo chmod 666 /home/ga/Documents/old_pos_export.csv

echo "✅ Created messy POS export CSV with ~150 transactions and ~45 customers (with duplicates)"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc with CSV file..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/old_pos_export.csv > /tmp/calc_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_task.log || true
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

echo "=== Legacy POS Rescue Task Setup Complete ==="
echo "📝 Task Overview:"
echo "  - Messy CSV with ~150 transactions from ~45 customers"
echo "  - Duplicate customers with name variations"
echo "  - Mixed date formats (MM/DD/YYYY, DD-MM-YY, YYYY-MM-DD)"
echo "  - Inconsistent currency formatting"
echo ""
echo "🎯 Your Goal:"
echo "  1. Clean and standardize customer names (Title Case, trimmed)"
echo "  2. Deduplicate customers (eliminate 8-15 duplicates)"
echo "  3. Standardize dates to YYYY-MM-DD format"
echo "  4. Clean amounts (numeric only, no symbols)"
echo "  5. Calculate Customer Lifetime Value (total per customer)"
echo "  6. Identify VIP customers (top 20% by spending)"
echo "  7. Create columns: CustomerID, CleanedName, TransactionDate, CleanAmount, VIP_Status, PaymentMethod"
echo "  8. Save as cleaned_customer_data.csv"
echo ""
echo "💡 Hints:"
echo "  - Use TRIM() and PROPER() for names"
echo "  - TEXT() for date standardization"
echo "  - SUBSTITUTE() to remove $ and USD"
echo "  - SUMIF() for customer lifetime value"
echo "  - PERCENTILE() for VIP threshold (80th percentile)"