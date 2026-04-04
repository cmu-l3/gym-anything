#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Science Fair Score Sheet Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop

# Create requirements document for reference
cat > /home/ga/Desktop/scoresheet_requirements.txt << 'EOF'
╔════════════════════════════════════════════════════════════════╗
║     SCIENCE FAIR SCORE SHEET - REQUIREMENTS                    ║
╚════════════════════════════════════════════════════════════════╝

URGENT: Science fair is THIS FRIDAY! Need 60 copies of judge score 
sheets printed by tomorrow morning.

REQUIRED FIELDS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📋 HEADER:
   • Form title (e.g., "Science Fair Judge Score Sheet")
   • School name: Hillside Elementary

👤 PARTICIPANT INFO:
   • Student Name: _______________
   • Project Number: _____

📊 SCORING CATEGORIES (each 0-25 points):
   1. Creativity (0-25 points)
      └─ Space for brief comments
   
   2. Scientific Method (0-25 points)
      └─ Space for brief comments
   
   3. Presentation Quality (0-25 points)
      └─ Space for brief comments
   
   4. Clarity of Explanation (0-25 points)
      └─ Space for brief comments

💯 TOTAL SCORE:
   • Total Score: _____ / 100 points

✍️  JUDGE INFORMATION:
   • Judge Name: _______________
   • Date: _______________
   • Judge Signature: _______________

DESIGN CONSTRAINTS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ Must fit on ONE PAGE (8.5" x 11" letter size)
✓ Professional appearance (district admins will use this!)
✓ Adequate space for HANDWRITING
✓ Clear sections with borders
✓ Easy to read when printed

SAVE AS: /home/ga/Documents/science_fair_scoresheet.ods
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Desktop/scoresheet_requirements.txt
sudo chmod 644 /home/ga/Desktop/scoresheet_requirements.txt

# Create initial blank ODS file
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet named "Score Sheet"
table = Table(name="Score Sheet")
doc.spreadsheet.addElement(table)

# Add empty rows to make it a proper spreadsheet
for _ in range(50):
    row = TableRow()
    for _ in range(12):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Save the file
doc.save("/home/ga/Documents/science_fair_scoresheet.ods")
print("✅ Created blank score sheet template")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/science_fair_scoresheet.ods
sudo chmod 666 /home/ga/Documents/science_fair_scoresheet.ods

# Display requirements in terminal notification (if xmessage available)
if command -v xmessage &> /dev/null; then
    su - ga -c "DISPLAY=:1 xmessage -timeout 10 -center -file /home/ga/Desktop/scoresheet_requirements.txt &" || true
fi

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/science_fair_scoresheet.ods > /tmp/calc_scoresheet_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_scoresheet_task.log || true
    # Don't exit - continue anyway
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit - continue anyway
fi

# Click on center of the screen to select current desktop (should be done in all tasks)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 400 click 1" || true
sleep 1

# Focus Calc window
echo "Focusing Calc window..."
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        # Maximize window for better workspace
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Ensure cursor is at A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

# Open requirements file in text editor for reference
echo "Opening requirements document..."
su - ga -c "DISPLAY=:1 xdg-open /home/ga/Desktop/scoresheet_requirements.txt &" || true
sleep 1

echo "=== Science Fair Score Sheet Task Setup Complete ==="
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  📋 TASK: Create Science Fair Judge Score Sheet          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "📝 Requirements document: ~/Desktop/scoresheet_requirements.txt"
echo "💾 Save to: ~/Documents/science_fair_scoresheet.ods"
echo ""
echo "Key Requirements:"
echo "  ✓ Header with form title"
echo "  ✓ Student Name & Project Number fields"
echo "  ✓ 4 scoring categories (25 pts each) with comment space"
echo "  ✓ Total Score field (100 pts)"
echo "  ✓ Judge Name, Date, Signature fields"
echo "  ✓ Professional formatting (borders, bold, merged cells)"
echo "  ✓ Must fit on ONE printed page"
echo ""
echo "💡 Tips:"
echo "  • Use Format → Merge Cells for headers"
echo "  • Use Format → Cells → Borders for structure"
echo "  • Use Ctrl+B for bold text"
echo "  • Right-click rows to adjust height for writing space"
echo ""