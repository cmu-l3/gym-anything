#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up School Read-a-thon Tracker Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directories
SHEET_DIR="/home/ga/Documents/Spreadsheets"
DOC_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$SHEET_DIR"
sudo -u ga mkdir -p "$DOC_DIR"

# Create the messy read-a-thon spreadsheet
SHEET_PATH="$SHEET_DIR/ReadAthon_Data.xlsx"

cat > /tmp/create_readathon.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import random
import sys

wb = Workbook()
ws = wb.active
ws.title = "Read-a-thon Data"

# Add headers
headers = ["Student Name", "Sponsor Name", "Pledge Type", "Pledge Amount", 
           "Books Read", "Payment Status", "Contact Info"]
for col, header in enumerate(headers, start=1):
    cell = ws.cell(row=1, column=col)
    cell.value = header
    cell.font = Font(bold=True)

# Sample data with realistic mess
students = [
    "Emma Johnson", "Liam Smith", "Olivia Brown", "Noah Davis", "Ava Wilson",
    "Ethan Martinez", "Sophia Anderson", "Mason Taylor", "Isabella Thomas", 
    "Lucas Jackson", "Mia White", "Aiden Harris", "Charlotte Martin", 
    "Jackson Thompson", "Amelia Garcia", "Logan Martinez", "Harper Robinson",
    "Sebastian Clark", "Evelyn Rodriguez", "Alexander Lewis", "Abigail Lee",
    "Benjamin Walker", "Emily Hall", "Daniel Allen", "Elizabeth Young"
]

sponsors = [
    "Grandma Patricia", "Uncle Mike", "Smith Family", "Johnson & Co", 
    "Aunt Sarah", "Mr. Thompson", "Local Bookstore", "Garcia Family",
    "Dr. Williams", "Martinez Family", "Tech Solutions Inc", "Brown Family",
    "Mrs. Anderson", "City Library Fund", "Davis Family", "Green Market",
    "Riverside Dental", "Wilson Family", "Taylor Family", "Community Bank",
    "Jones Family", "Miller Family", "Moore Family", "Jackson Family",
    "Martin Family", "Lee Family", "Perez Family", "White Family"
]

contact_info = [
    "patricia.j@email.com", "(555) 123-4567", "mike.smith@email.com",
    "contact@johnsonco.com", "sarah.m@email.com", "555-234-5678",
    "bookstore@local.com", "555-345-6789", "dr.williams@clinic.com",
    "martinez_fam@email.com", "info@techsolutions.com", "(555) 456-7890",
    "anderson.sue@email.com", "library@city.gov", "555-567-8901",
    "greenmarket@email.com", "riverside.dental@email.com", "555-678-9012",
    "taylor_family@email.com", "info@communitybank.com", "jones@email.com",
    "555-789-0123", "moore.family@email.com", "jackson_fam@email.com",
    "555-890-1234", "lee.family@email.com", "perez@email.com", "555-901-2345"
]

# Generate 28 rows of data
for i in range(28):
    row = i + 2
    student = random.choice(students)
    sponsor = sponsors[i] if i < len(sponsors) else random.choice(sponsors)
    
    # 60% per-book, 40% flat
    pledge_type = "Per Book" if random.random() < 0.6 else "Flat"
    
    # Pledge amounts with inconsistent formatting
    if pledge_type == "Per Book":
        amounts = ["$2", "2", "$2.00", "$3", "3", "$1", "1.50", "$1.50"]
        pledge_amount = random.choice(amounts)
    else:
        amounts = ["$50", "50", "$25", "25.00", "$75", "100", "$30", "40"]
        pledge_amount = random.choice(amounts)
    
    # Books read - some students didn't participate (blank)
    if random.random() < 0.15:  # 15% didn't participate
        books_read = None
    else:
        books_read = random.randint(3, 25)
    
    # Payment status - 40% paid, 60% unpaid
    if random.random() < 0.4:
        payment_status = "Paid"
    elif random.random() < 0.5:
        payment_status = "Pending"
    else:
        payment_status = ""
    
    contact = contact_info[i] if i < len(contact_info) else random.choice(contact_info)
    
    ws.cell(row=row, column=1, value=student)
    ws.cell(row=row, column=2, value=sponsor)
    ws.cell(row=row, column=3, value=pledge_type)
    ws.cell(row=row, column=4, value=pledge_amount)
    ws.cell(row=row, column=5, value=books_read)
    ws.cell(row=row, column=6, value=payment_status)
    ws.cell(row=row, column=7, value=contact)

# Add instructions below data
instruction_row = 32
ws.cell(row=instruction_row, column=1, value="INSTRUCTIONS:")
ws.cell(row=instruction_row, column=1).font = Font(bold=True, size=12)

ws.cell(row=instruction_row + 1, column=1, 
        value="1. Add 'Amount Owed' column in Column H with formulas:")
ws.cell(row=instruction_row + 2, column=1, 
        value="   - Per Book: Pledge Amount × Books Read")
ws.cell(row=instruction_row + 3, column=1, 
        value="   - Flat: Just the Pledge Amount")
ws.cell(row=instruction_row + 4, column=1, 
        value="   - Handle blank/zero books read (should = $0)")

ws.cell(row=instruction_row + 6, column=1, 
        value="2. Create summary section (around row 35) showing:")
ws.cell(row=instruction_row + 7, column=1, 
        value="   - Total Amount Pledged")
ws.cell(row=instruction_row + 8, column=1, 
        value="   - Total Amount Collected (status = 'Paid')")
ws.cell(row=instruction_row + 9, column=1, 
        value="   - Total Amount Outstanding (status ≠ 'Paid')")

ws.cell(row=instruction_row + 11, column=1, 
        value="3. OPTIONAL: Create collection letters for unpaid sponsors")

# Adjust column widths
ws.column_dimensions['A'].width = 18
ws.column_dimensions['B'].width = 22
ws.column_dimensions['C'].width = 12
ws.column_dimensions['D'].width = 14
ws.column_dimensions['E'].width = 12
ws.column_dimensions['F'].width = 16
ws.column_dimensions['G'].width = 25

wb.save(sys.argv[1])
print(f"Read-a-thon spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_readathon.py
python3 /tmp/create_readathon.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Read-a-thon spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_readathon_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_readathon_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Read-a-thon Tracker Task Setup Complete ==="
echo "📊 SCENARIO:"
echo "   You're a parent volunteer coordinating your child's school read-a-thon."
echo "   The event happened 2 weeks ago. You inherited this messy spreadsheet from"
echo "   paper pledge forms. Some sponsors paid, many haven't. The principal needs"
echo "   a status update tomorrow!"
echo ""
echo "📝 YOUR TASK:"
echo "   1. Calculate 'Amount Owed' for each sponsor (Column H)"
echo "      - 'Per Book' pledges: multiply by books read"
echo "      - 'Flat' pledges: just the pledge amount"
echo "      - Handle students who didn't read (blank books = $0)"
echo ""
echo "   2. Create summary statistics (around row 35):"
echo "      - Total Amount Pledged"
echo "      - Total Amount Collected (where status = 'Paid')"
echo "      - Total Amount Outstanding"
echo ""
echo "   3. BONUS: Create collection letters for unpaid sponsors"
echo "      Save as: /home/ga/Documents/TextDocuments/Collection_Letters.docx"
echo ""
echo "⏰ The principal is waiting! Good luck!"