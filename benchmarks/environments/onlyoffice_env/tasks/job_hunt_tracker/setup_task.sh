#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Job Hunt Tracker Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial job application tracking spreadsheet
SHEET_PATH="$WORKSPACE_DIR/job_applications.xlsx"

cat > /tmp/create_job_tracker.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill
from datetime import datetime, timedelta
import random
import sys

wb = Workbook()
ws = wb.active
ws.title = "Applications"

# Set column widths for readability
ws.column_dimensions['A'].width = 20
ws.column_dimensions['B'].width = 25
ws.column_dimensions['C'].width = 15
ws.column_dimensions['D'].width = 15
ws.column_dimensions['E'].width = 18
ws.column_dimensions['F'].width = 18
ws.column_dimensions['G'].width = 18
ws.column_dimensions['H'].width = 20
ws.column_dimensions['I'].width = 18
ws.column_dimensions['J'].width = 22
ws.column_dimensions['K'].width = 15

# Add title row
ws['A1'] = "Sarah's Job Application Tracker"
ws['A1'].font = Font(size=14, bold=True)
ws.merge_cells('A1:E1')

# Add headers for existing columns (row 2)
headers = [
    "Company",
    "Position Title",
    "Date Applied",
    "Source",
    "Resume Version"
]

header_fill = PatternFill(start_color="4472C4", end_color="4472C4", fill_type="solid")
header_font = Font(color="FFFFFF", bold=True)

for col_idx, header in enumerate(headers, start=1):
    cell = ws.cell(row=2, column=col_idx, value=header)
    cell.fill = header_fill
    cell.font = header_font
    cell.alignment = Alignment(horizontal='center', vertical='center')

# Leave F, G, H empty (user needs to add headers: Status, Date of Response, Next Action)
# Add placeholder text to indicate what's needed
ws['F2'] = "[Add Header: Status]"
ws['G2'] = "[Add Header: Date of Response]"
ws['H2'] = "[Add Header: Next Action]"

# Sample realistic job application data
companies = [
    "TechCorp Solutions", "DataStream Inc", "CloudNine Systems", 
    "Innovate Labs", "Digital Dynamics", "FutureWorks", 
    "Quantum Analytics", "Bright Horizon Tech", "Nexus Software",
    "Vertex AI", "Summit Technologies", "Catalyst Digital"
]

positions = [
    "Senior Software Engineer", "Product Manager", "Data Analyst",
    "DevOps Engineer", "UX Designer", "Marketing Manager",
    "Project Manager", "Business Analyst", "QA Engineer",
    "Technical Writer", "Sales Engineer", "Customer Success Manager"
]

sources = ["LinkedIn", "Indeed", "Company Site", "Referral"]
resume_versions = ["PM-focused", "Tech-focused", "Balanced"]

# Generate 12 rows of application data (rows 3-14)
base_date = datetime.now() - timedelta(days=120)  # Started 4 months ago

for row_idx in range(3, 15):
    company = companies[row_idx - 3]
    position = positions[row_idx - 3]
    
    # Varied application dates over past 4 months
    days_ago = random.randint(5, 120)
    date_applied = base_date + timedelta(days=(120 - days_ago))
    
    source = random.choice(sources)
    resume_ver = random.choice(resume_versions)
    
    ws.cell(row=row_idx, column=1, value=company)
    ws.cell(row=row_idx, column=2, value=position)
    ws.cell(row=row_idx, column=3, value=date_applied)
    ws.cell(row=row_idx, column=3).number_format = 'MM/DD/YYYY'
    ws.cell(row=row_idx, column=4, value=source)
    ws.cell(row=row_idx, column=5, value=resume_ver)

# Add instructions in a separate area
ws['A16'] = "INSTRUCTIONS:"
ws['A16'].font = Font(bold=True, size=11)

instructions = [
    "1. Add missing headers: 'Status', 'Date of Response', 'Next Action' in columns F, G, H",
    "2. Add 'Days Since Applied' column in column I with formula =TODAY()-C3",
    "3. Create Summary Statistics section starting at J3:",
    "   - J3: 'Total Applications'  → K3: =COUNTA(A3:A14)",
    "   - J4: 'Response Rate'  → K4: =(COUNTIF(F3:F14,\"Phone Screen\")+COUNTIF(F3:F14,\"Interview Scheduled\"))/COUNTA(A3:A14)",
    "   - J5: 'Interviews Scheduled'  → K5: =COUNTIF(F3:F14,\"Interview Scheduled\")",
    "   - J6: 'Rejections'  → K6: =COUNTIF(F3:F14,\"Rejected\")",
    "4. Fill Status column (F) with values: Applied, Phone Screen, Interview Scheduled, Rejected, Offer",
    "5. Add data validation dropdown to Status column (F3:F14)",
    "6. Apply conditional formatting:",
    "   - RED background: Status='Applied' AND Days Since Applied ≥ 14",
    "   - GREEN background: Status='Interview Scheduled'",
    "7. Sort data by Date Applied (oldest to newest)",
    "8. Save with Ctrl+S"
]

for idx, instruction in enumerate(instructions, start=17):
    ws[f'A{idx}'] = instruction
    ws[f'A{idx}'].font = Font(size=9)

wb.save(sys.argv[1])
print(f"Job tracker spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_job_tracker.py
python3 /tmp/create_job_tracker.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Job application tracker created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_jobtracker_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_jobtracker_task.log || true
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

echo "=== Job Hunt Tracker Task Setup Complete ==="
echo ""
echo "📊 SCENARIO:"
echo "Sarah has been job hunting for 4 months with scattered tracking."
echo "Help her create a functional application tracker with:"
echo "  • Complete column headers"
echo "  • Status tracking with validation"
echo "  • Automated calculations (days waiting, success metrics)"
echo "  • Visual highlighting (urgent follow-ups, upcoming interviews)"
echo ""
echo "📝 KEY TASKS:"
echo "  1. Complete missing headers in F, G, H"
echo "  2. Add Days Since Applied calculation (column I)"
echo "  3. Create Summary Statistics with formulas (J3:K6)"
echo "  4. Fill Status column with realistic values"
echo "  5. Apply conditional formatting (RED for urgent, GREEN for interviews)"
echo "  6. Add data validation to Status column"
echo "  7. Save the spreadsheet (Ctrl+S)"
echo ""
echo "See instructions in the spreadsheet (starting row 16) for details."