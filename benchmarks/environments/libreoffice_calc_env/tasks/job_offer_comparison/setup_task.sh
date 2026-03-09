#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Job Offer Comparison Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create messy job tracking spreadsheet with realistic data
# Uses Python with odfpy to create ODS file with proper structure
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
import datetime

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add main sheet
table = Table(name="Job Search")
doc.spreadsheet.addElement(table)

# Helper function to add cell with value
def add_cell(row, value, value_type='string'):
    cell = TableCell(valuetype=value_type)
    if value is not None:
        if value_type == 'float':
            cell.setAttribute('value', str(value))
            p = P(text=str(value))
        elif value_type == 'date':
            cell.setAttribute('datevalue', value)
            p = P(text=value)
        else:
            p = P(text=str(value))
        cell.addElement(p)
    row.addElement(cell)
    return cell

# Header row
header_row = TableRow()
headers = ["Company Name", "Position", "Applied Date", "Status", "Salary/Rate", "Bonus", "Benefits", "Notes"]
for header in headers:
    add_cell(header_row, header, 'string')
table.addElement(header_row)

# Job applications data (messy, realistic)
applications = [
    ["TechStart Inc", "Senior Software Engineer", "2024-01-15", "Offer Received", "75000", "$5000 signing", "Good healthcare", "Startup, equity included"],
    ["DataCorp", "Data Analyst", "2024-01-20", "Offer Received", "82000", "10% annual", "Basic benefits", "Large company, stable"],
    ["WebDesigns LLC", "Frontend Developer", "2024-01-08", "Rejected", "$35/hr", "None", "Contractor - no benefits", "Too low"],
    ["CloudSystems", "DevOps Engineer", "2024-01-12", "Phone Screen", "$45/hour", "Performance bonus", "Full benefits", "Interesting tech stack"],
    ["StartupXYZ", "Full Stack Developer", "2024-01-25", "Applied", "$28/hr", "None", "Minimal", "Remote position"],
    ["Enterprise Co", "Software Engineer", "2024-01-05", "Interviewing", "95000", "$10000 signing", "Excellent benefits", "3rd round interview"],
    ["Digital Agency", "Web Developer", "2024-01-18", "Applied", "$32.50/hour", "Project bonuses", "Basic", "Contract-to-hire"],
    ["FinTech Solutions", "Backend Developer", "2024-01-10", "Rejected", "88000", "15% annual", "Good", "Culture fit issues"],
    ["Mobile Apps Inc", "iOS Developer", "2024-01-22", "Phone Screen", "78000", "5000", "Standard", "Interesting projects"],
    ["AI Research Lab", "ML Engineer", "2024-01-03", "Interviewing", "105000", "Equity", "Premium", "Dream job potential"],
    ["Consulting Group", "Tech Consultant", "2024-01-28", "Applied", "$55/hr", "Quarterly bonus", "Consultant package", "Travel required"],
]

for app in applications:
    row = TableRow()
    for i, value in enumerate(app):
        if i == 2:  # Date column
            add_cell(row, value, 'string')  # Keep as string for realistic messiness
        elif i == 4:  # Salary column - keep as string to preserve formatting
            add_cell(row, value, 'string')
        else:
            add_cell(row, value, 'string')
    table.addElement(row)

# Add some empty rows for work space
for _ in range(15):
    row = TableRow()
    for _ in range(10):
        add_cell(row, None, 'string')
    table.addElement(row)

# Save the file
output_path = "/home/ga/Documents/job_search_tracker.ods"
doc.save(output_path)
print(f"✅ Created job search tracker: {output_path}")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/job_search_tracker.ods
sudo chmod 666 /home/ga/Documents/job_search_tracker.ods

# Verify file was created
if [ -f "/home/ga/Documents/job_search_tracker.ods" ]; then
    echo "✅ Job search tracker created successfully"
    ls -lh /home/ga/Documents/job_search_tracker.ods
else
    echo "❌ ERROR: Failed to create job search tracker"
    exit 1
fi

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/job_search_tracker.ods > /tmp/calc_job_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_job_task.log || true
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

# Position cursor at A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Job Offer Comparison Task Setup Complete ==="
echo ""
echo "📋 Your Task:"
echo "  1. Convert hourly rates to annual (multiply by 2080)"
echo "  2. Calculate total compensation for:"
echo "     • Company A (TechStart Inc): Base + Bonus + Benefits"
echo "     • Company B (DataCorp): Base + Bonus + Benefits"
echo "  3. Add days-since-application formula using TODAY()"
echo "  4. Apply currency formatting to salaries"
echo ""
echo "💡 Key Info:"
echo "  • Hourly to annual: rate × 2080 hours/year"
echo "  • Company A benefits: ~$8,000"
echo "  • Company B benefits: ~$6,000"
echo "  • 10% bonus on $82,000 = $8,200"
echo ""
echo "⏰ You have 180 seconds. Good luck with your decision!"