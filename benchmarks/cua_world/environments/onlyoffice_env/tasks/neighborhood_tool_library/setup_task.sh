#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Neighborhood Tool Library Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial blank spreadsheet
SHEET_PATH="$WORKSPACE_DIR/neighborhood_tool_library.xlsx"

cat > /tmp/create_tool_library.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill
import sys

wb = Workbook()
ws = wb.active
ws.title = "Tool Library"

# Add a title/instruction row to make task clearer
ws['A1'] = "Neighborhood Tool Library Tracker"
ws['A1'].font = Font(size=14, bold=True)

# Add task instructions in a merged cell or comment
ws['A3'] = "Instructions: Track shared tools, their owners, checkout status, and calculate days out for overdue items (>7 days)."
ws['A3'].font = Font(size=10, italic=True)
ws['A3'].alignment = Alignment(wrap_text=True)

# Leave the actual data entry to the agent
# They need to create column headers starting at row 5 or wherever they choose

# Add a subtle hint about structure (but not pre-filled headers)
ws['A5'] = "[Create your column headers here: Tool Name, Owner, Status, etc.]"
ws['A5'].font = Font(size=9, italic=True, color="808080")

# Set some column widths for usability
ws.column_dimensions['A'].width = 20
ws.column_dimensions['B'].width = 15
ws.column_dimensions['C'].width = 15
ws.column_dimensions['D'].width = 15
ws.column_dimensions['E'].width = 15
ws.column_dimensions['F'].width = 12
ws.column_dimensions['G'].width = 20

wb.save(sys.argv[1])
print(f"Tool library spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_tool_library.py
python3 /tmp/create_tool_library.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_tool_library.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_tool_library.log || true
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

echo "=== Neighborhood Tool Library Task Setup Complete ==="
echo ""
echo "📝 TASK SCENARIO:"
echo "Your neighborhood has 5 families sharing expensive tools to save money."
echo "Last month, a \$400 chainsaw went missing for 3 weeks because nobody tracked who had it."
echo "You volunteered to create a tracking spreadsheet to prevent this from happening again."
echo ""
echo "📋 YOUR TASK:"
echo "1. Create column headers: Tool Name, Owner, Current Status, Borrowed By, Checkout Date, Days Out, Notes"
echo "2. Enter these 10 tools with their owners:"
echo "   • Chainsaw (Martinez)"
echo "   • Pressure Washer (Chen)"
echo "   • Tile Saw (Johnson)"
echo "   • Extension Ladder 24ft (Park)"
echo "   • Power Drill Set (Rodriguez)"
echo "   • Leaf Blower (Martinez)"
echo "   • Wet/Dry Vacuum (Thompson)"
echo "   • Circular Saw (Chen)"
echo "   • Hedge Trimmer (Park)"
echo "   • Post Hole Digger (Johnson)"
echo ""
echo "3. Record these 4 current checkouts (calculate dates from today):"
echo "   • Pressure Washer: checked out to Rodriguez, 3 days ago"
echo "   • Extension Ladder: checked out to Thompson, 5 days ago"
echo "   • Power Drill Set: checked out to Martinez, 9 days ago (OVERDUE!)"
echo "   • Circular Saw: checked out to Johnson, 2 days ago"
echo ""
echo "4. For available items: mark status as 'Available' or similar, Borrowed By as 'N/A'"
echo ""
echo "5. Create a 'Days Out' calculated field using =TODAY()-[checkout_date] formula"
echo "   (Should show 0 or blank for available items)"
echo ""
echo "6. Add formatting/highlighting to flag items that have been out >7 days"
echo ""
echo "7. Save the spreadsheet (Ctrl+S)"
echo ""
echo "💡 TIP: The neighborhood agreed on a 7-day return policy to keep tools circulating."