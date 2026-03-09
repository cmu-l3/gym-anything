#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Photographer Shoot Coordinator Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Photography"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with photographer data including conflicts
SHEET_PATH="$WORKSPACE_DIR/shoot_master_schedule.xlsx"

cat > /tmp/create_photographer_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill
import sys

wb = Workbook()
ws = wb.active
ws.title = "Shoots"

# Add headers with formatting
headers = ["Date", "Client", "Shoot Type", "Time", "Location", 
           "Equipment Needed", "Rental Cost", "Assistant Status", 
           "Payment Status", "Weather Backup"]

for col_idx, header in enumerate(headers, start=1):
    cell = ws.cell(row=1, column=col_idx, value=header)
    cell.font = Font(bold=True, size=11)
    cell.alignment = Alignment(horizontal='center', vertical='center')
    cell.fill = PatternFill(start_color="D9E1F2", end_color="D9E1F2", fill_type="solid")

# Set column widths
ws.column_dimensions['A'].width = 12
ws.column_dimensions['B'].width = 15
ws.column_dimensions['C'].width = 15
ws.column_dimensions['D'].width = 10
ws.column_dimensions['E'].width = 18
ws.column_dimensions['F'].width = 25
ws.column_dimensions['G'].width = 12
ws.column_dimensions['H'].width = 18
ws.column_dimensions['I'].width = 20
ws.column_dimensions['J'].width = 30

# Add shoot data with INTENTIONAL ISSUES that need fixing
shoot_data = [
    # Martinez Wedding - TIME NEEDS UPDATE (2:00 PM should be 11:00 AM)
    ["06/15/2024", "Martinez Wedding", "Wedding", "2:00 PM", 
     "Riverside Gardens", "24-70mm, 70-200mm, flash kit", 150, 
     "Yes - Sarah confirmed", "$1000 deposit received, $1200 due on shoot", 
     "N/A (indoor venue)"],
    
    # Chen Family - EQUIPMENT CONFLICT (70-200mm also needed here), ASSISTANT UNAVAILABLE
    ["06/22/2024", "Chen Family", "Outdoor Portraits", "5:00 PM",
     "Sunset Beach", "70-200mm, 50mm f/1.8", 75,
     "Yes - Sarah confirmed", "$300 due on shoot",
     "Rainy: Covered pavilion at Lakeside Park"],
    
    # Taylor Engagement - COST NEEDS UPDATE ($125 should be $175 for premium lens)
    ["06/29/2024", "Taylor Engagement", "Engagement", "10:00 AM",
     "Downtown", "24-70mm, 50mm f/1.4 (premium)", 125,
     "No assistant needed", "$800 total, $400 due on shoot",
     "N/A (urban setting)"]
]

for row_idx, data in enumerate(shoot_data, start=2):
    for col_idx, value in enumerate(data, start=1):
        cell = ws.cell(row=row_idx, column=col_idx, value=value)
        cell.alignment = Alignment(vertical='top', wrap_text=True)

# Add summary section
ws.cell(row=5, column=1, value="SUMMARY").font = Font(bold=True, size=12)
ws.cell(row=6, column=1, value="Total Equipment Rental:")
ws.cell(row=6, column=2, value="=SUM(G2:G4)")
ws.cell(row=6, column=2).font = Font(bold=True)

ws.cell(row=7, column=1, value="Total Expected Revenue:")
ws.cell(row=7, column=2, value="$2,100")
ws.cell(row=7, column=2).font = Font(bold=True)

ws.cell(row=8, column=1, value="Issues to Resolve:")
ws.cell(row=9, column=1, value="1. Martinez time conflict")
ws.cell(row=10, column=1, value="2. 70-200mm lens double-booked")
ws.cell(row=11, column=1, value="3. Taylor rental cost outdated")
ws.cell(row=12, column=1, value="4. Chen assistant unavailable")

# Add instruction notes
ws.cell(row=14, column=1, value="URGENT ACTIONS NEEDED:").font = Font(bold=True, size=11, color="FF0000")
ws.cell(row=15, column=1, value="• Update Martinez wedding time to 11:00 AM")
ws.cell(row=16, column=1, value="• Resolve equipment conflict (rent 2nd lens OR substitute)")
ws.cell(row=17, column=1, value="• Update Taylor rental to $175 for premium lens")
ws.cell(row=18, column=1, value="• Mark Chen Family assistant status as unavailable")
ws.cell(row=19, column=1, value="• Create client timeline document for Chen Family")

wb.save(sys.argv[1])
print(f"Photographer spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_photographer_sheet.py
python3 /tmp/create_photographer_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Photographer schedule created at: $SHEET_PATH"

# Create instruction file
INSTRUCTIONS_PATH="$WORKSPACE_DIR/URGENT_READ_ME.txt"
cat > "$INSTRUCTIONS_PATH" << 'EOF'
PHOTOGRAPHER SHOOT COORDINATOR - URGENT ISSUES
================================================

SITUATION: You have 3 shoots booked this month worth $2,100 total revenue.
Multiple conflicts emerged this morning that MUST be resolved.

FILES TO WORK WITH:
1. shoot_master_schedule.xlsx - Main coordination spreadsheet
2. chen_family_shoot_plan.docx - Client-facing timeline (YOU MUST CREATE THIS)

PROBLEMS TO FIX:

1. MARTINEZ WEDDING (06/15/2024)
   - Client texted: Ceremony moved from 2:00 PM to 11:00 AM
   - UPDATE the Time column to 11:00 AM

2. EQUIPMENT CONFLICT
   - You double-booked 70-200mm lens for June 15 AND June 22
   - RESOLVE by either:
     Option A: Rent second 70-200mm for June 22 (add $75)
     Option B: Use substitute lens like 85mm f/1.8 (add $50)
   - UPDATE Equipment Needed and Rental Cost columns

3. TAYLOR ENGAGEMENT (06/29/2024)
   - Client upgraded to premium package
   - Now needs 50mm f/1.4 instead of f/1.8
   - Rental cost increases from $125 to $175
   - UPDATE Rental Cost column

4. CHEN FAMILY ASSISTANT (06/22/2024)
   - Sarah just told you she's UNAVAILABLE June 22
   - MARK in Assistant Status column that you need backup

5. CLIENT COMMUNICATION
   - Chen Family is ANXIOUS about weather for their outdoor shoot
   - CREATE professional document: chen_family_shoot_plan.docx
   - INCLUDE:
     * Professional header with shoot details
     * Timeline of the session (5:00 PM start at Sunset Beach)
     * Weather backup plan (Lakeside Park pavilion)
     * Reassuring language about monitoring forecast

WHAT SUCCESS LOOKS LIKE:
- Spreadsheet shows all 4 conflicts resolved
- Cost calculations updated and accurate
- Professional client document created for Chen Family
- Both files saved

Your reputation and $2,100 revenue depend on getting this right!
EOF

chown ga:ga "$INSTRUCTIONS_PATH"

echo "✅ Instructions created at: $INSTRUCTIONS_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_photographer_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_photographer_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Photographer Shoot Coordinator Task Setup Complete ==="
echo "📸 SCENARIO: You're a photographer with 3 shoots and multiple urgent conflicts!"
echo ""
echo "📋 FILES:"
echo "  - Main spreadsheet: $SHEET_PATH"
echo "  - Instructions: $INSTRUCTIONS_PATH"
echo ""
echo "🚨 PROBLEMS TO FIX:"
echo "  1. Martinez Wedding: Update time from 2:00 PM → 11:00 AM"
echo "  2. Equipment conflict: 70-200mm lens double-booked (resolve it)"
echo "  3. Taylor Engagement: Update rental cost $125 → $175"
echo "  4. Chen Family: Mark assistant as unavailable"
echo "  5. Create chen_family_shoot_plan.docx with timeline & weather backup"
echo ""
echo "💰 Stakes: $2,100 revenue and your professional reputation!"