#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Elderly Medication Reconciliation Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the messy starter spreadsheet with realistic medication data
SHEET_PATH="$WORKSPACE_DIR/dad_medications_messy.xlsx"

cat > /tmp/create_med_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment
from datetime import datetime, timedelta
import sys

wb = Workbook()
ws = wb.active
ws.title = "Medications"

# Messy header row (inconsistent naming, some columns present)
headers = [
    "Med Name", "Dose", "How Often?", "Dr", "Pharmacy", 
    "Why Taking?", "Status?", "Started", "Last Refill", "Next Refill", "Notes"
]
ws.append(headers)

# Add 12 medications with intentionally incomplete/messy data
# This mimics real-world chaos: inconsistent formatting, missing data, unclear status
current_date = datetime.now()

meds_data = [
    # Active medications (10) - varying levels of completeness
    ["Metformin", "500mg", "2x daily", "Dr. Chen (Endo)", "CVS Main St", 
     "Diabetes Type 2", "Active", "01/15/2022", "03/01/2024", "03/29/2024", 
     "Take with food to avoid stomach upset"],
    
    ["Lisinopril", "10mg", "once daily", "", "CVS Main St", 
     "Blood pressure", "Active", "03/2021", "02/28/2024", "03/28/2024", ""],
    
    ["Atorvastatin", "20 mg", "bedtime", "Dr. Williams - Cardiology", "Walgreens Oak Ave", 
     "High cholesterol", "Active", "", "03/05/2024", "", "Can cause muscle pain"],
    
    ["Gabapentin", "300mg", "3x daily", "Dr. Martinez (Neuro)", "CVS Main St", 
     "Nerve pain / neuropathy", "Active", "06/2023", "03/08/2024", "04/05/2024", 
     "Makes him drowsy, take at night"],
    
    ["Aspirin", "81mg", "", "Dr. Williams", "CVS Main St", 
     "Heart protection", "Active", "", "03/15/2024", "04/12/2024", "Baby aspirin"],
    
    ["Omeprazole", "20mg", "morning", "Dr. Chen", "", 
     "Acid reflux / GERD", "Active", "2020", "02/20/2024", "03/20/2024", ""],
    
    ["Metoprolol", "25mg", "twice a day", "Williams", "CVS Main St", 
     "", "Active", "03/2021", "03/10/2024", "04/07/2024", "Beta blocker"],
    
    ["Vitamin D3", "2000IU", "daily", "", "Costco", 
     "Vitamin deficiency", "Active", "", "", "", "Over the counter"],
    
    ["Tramadol", "50mg", "as needed for pain", "Dr. Martinez", "CVS Main St", 
     "Pain relief PRN", "Active", "06/2023", "03/18/2024", "04/15/2024", 
     "Only when pain is severe. Do not drive after taking."],
    
    ["Amlodipine", "5mg", "once daily", "Cardiology", "Walgreens Oak Ave", 
     "High BP", "?", "02/2022", "03/12/2024", "", ""],
    
    # Discontinued medications (2)
    ["Hydrochlorothiazide", "25mg", "morning", "Dr. Williams", "CVS Main St", 
     "Blood pressure", "Discontinued", "01/2021", "01/05/2024", "", 
     "Stopped Jan 2024 - made him dizzy"],
    
    ["Warfarin", "5mg", "evening", "Dr. Williams - Cardiology", "Walgreens Oak Ave", 
     "Blood thinner", "STOPPED", "05/2020", "12/01/2023", "", 
     "Switched to different medication in Dec 2023"],
]

for med in meds_data:
    ws.append(med)

# Make it look like someone started working on it but didn't finish
# No special formatting, no formulas, messy layout

ws.column_dimensions['A'].width = 15
ws.column_dimensions['B'].width = 10
ws.column_dimensions['K'].width = 30

wb.save(sys.argv[1])
print(f"Messy medication spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_med_sheet.py
python3 /tmp/create_med_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Messy medication spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_medrecon_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_medrecon_task.log || true
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

echo "=== Elderly Medication Reconciliation Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "  Your 76-year-old father was recently in the ER for dizziness."
echo "  The doctor suspects a medication interaction."
echo "  His primary care appointment is in 2 weeks."
echo "  You need to create a professional medication list."
echo ""
echo "📝 YOUR TASKS:"
echo "  1. Complete ALL missing information for active medications"
echo "     (doctor names, pharmacies, dates, purposes)"
echo "  2. Separate Active medications from Discontinued"
echo "     (create separate sections or sheets)"
echo "  3. Add professional formatting:"
echo "     - Bold and freeze header row"
echo "     - Adjust column widths"
echo "     - Add borders to all cells"
echo "  4. Add safety features:"
echo "     - Highlight medications due for refill in next 7 days"
echo "     - Flag potential interactions (highlight 2+ rows)"
echo "     - Mark PRN (as-needed) medications differently"
echo "  5. Create summary section with FORMULAS:"
echo "     - Total number of active medications"
echo "     - Number of daily vs PRN medications"
echo "     - Medications needing refill soon"
echo "  6. Save as: dad_medications_reconciled.xlsx"
echo ""
echo "⚠️  CRITICAL: This is for a medical appointment - accuracy matters!"