#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Internet Troubleshooting Log Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create a blank spreadsheet (user will create structure themselves)
SHEET_PATH="$WORKSPACE_DIR/internet_log.xlsx"

cat > /tmp/create_blank_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

wb = Workbook()
ws = wb.active
ws.title = "Internet Log"

# Start with completely blank sheet - user creates everything
# This makes the task more realistic and tests their ability to structure data

wb.save(sys.argv[1])
print(f"Blank spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_blank_sheet.py
python3 /tmp/create_blank_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_internet_log_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_internet_log_task.log || true
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

echo "=== Internet Troubleshooting Log Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "Your internet has been unreliable for weeks. Your ISP claims 'no problems detected'"
echo "but you're experiencing frequent issues. Create a troubleshooting log to document"
echo "the problems systematically."
echo ""
echo "📝 REQUIRED ELEMENTS:"
echo ""
echo "1. INCIDENT LOG TABLE with exact column headers (row 1):"
echo "   A: Date"
echo "   B: Time"
echo "   C: Issue Type"
echo "   D: Download Speed (Mbps)"
echo "   E: Upload Speed (Mbps)"
echo "   F: Expected Speed (Mbps)"
echo "   G: Duration (minutes)"
echo "   H: Devices Affected"
echo "   I: Activity When Occurred"
echo "   J: Troubleshooting Tried"
echo ""
echo "2. Enter at least 8 sample incident records (rows 2-9 minimum)"
echo "   - Issue Type should include: 'Complete Outage', 'Slow Speed', 'Intermittent', 'High Latency'"
echo "   - Your plan is 500 Mbps down / 50 Mbps up (use in Expected Speed column)"
echo "   - Include variety in times, dates, and issue types"
echo "   - At least one incident with speed < 250 Mbps"
echo "   - At least one incident with duration > 30 minutes"
echo ""
echo "3. SUMMARY STATISTICS (starting around row 20):"
echo "   A20: 'Total Incidents:' → B20: COUNT formula"
echo "   A21: 'Average Downtime (min):' → B21: AVERAGE formula"
echo "   A22: 'Average Download Speed:' → B22: AVERAGE formula"
echo "   A23: 'Service Reliability %:' → B23: formula with 43,200 minutes (30 days)"
echo ""
echo "4. CONDITIONAL FORMATTING:"
echo "   - Highlight Download Speed cells (column D) in RED if < 250 Mbps"
echo "   - Highlight Duration cells (column G) in ORANGE if > 30 minutes"
echo ""
echo "5. Save the file (Ctrl+S)"
echo ""
echo "💡 TIP: This log should look professional enough to send to your ISP support team."