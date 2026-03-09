#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Ham Radio Contest Log Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with messy raw data
SHEET_PATH="$WORKSPACE_DIR/fieldday_raw_log.xlsx"

cat > /tmp/create_ham_log.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

wb = Workbook()
ws = wb.active
ws.title = "Field Day Log"

# Headers
ws['A1'] = "Time"
ws['B1'] = "Frequency"
ws['C1'] = "Mode"
ws['D1'] = "Call Sign"
ws['E1'] = "RST Sent"
ws['F1'] = "Section"

# Sample contacts with intentional messiness in formatting
# Mix of 12-hour ("2:30 PM"), 24-hour ("14:45"), and compressed ("1530") time formats
# Mix of frequency formats: "14.250", "14250 kHz", "7.185 MHz"
# Mix of modes: SSB, USB, LSB (should normalize to SSB), CW, FT8
contacts = [
    ["2:30 PM", "14.250", "SSB", "K4ABC", "59", "NC"],
    ["2:45 PM", "14.285", "USB", "W1XYZ", "59", "CT"],
    ["14:50", "14250 kHz", "SSB", "N2DEF", "59", "NY"],
    ["1505", "14.320", "USB", "KA3GHI", "59", "PA"],
    ["3:20 PM", "7.185 MHz", "LSB", "W4JKL", "59", "VA"],
    ["15:30", "14.050", "CW", "K5MNO", "5NN", "TX"],
    ["1545", "14.045", "CW", "N6PQR", "5NN", "CA"],
    ["4:00 PM", "14.074", "FT8", "W7STU", "---", "WA"],
    ["16:15", "14.078", "FT8", "KA8VWX", "---", "OH"],
    ["4:30 PM", "21.300", "USB", "K9YZA", "59", "IL"],
    ["16:45", "21.350", "SSB", "W0BCD", "59", "MN"],
    ["1700", "14.290", "SSB", "K4ABC", "59", "NC"],  # Duplicate: K4ABC on 20m
    ["5:15 PM", "7.250", "LSB", "N1EFG", "59", "ME"],
    ["17:30", "7200 kHz", "LSB", "K2HIJ", "59", "NJ"],
    ["5:45 PM", "7.045", "CW", "W3KLM", "5NN", "MD"],
    ["18:00", "7.050", "CW", "KA4NOP", "5NN", "TN"],
    ["6:15 PM", "7.200", "LSB", "W4JKL", "59", "VA"],  # Duplicate: W4JKL on 40m
    ["18:30", "21.325", "USB", "K5QRS", "59", "OK"],
    ["1845", "21.375", "SSB", "N6TUV", "59", "NV"],
    ["7:00 PM", "21.074", "FT8", "W7WXY", "---", "OR"],
    ["19:15", "14.265", "USB", "KA8ZAB", "59", "MI"],
    ["7:30 PM", "14.275", "SSB", "K9CDE", "59", "WI"],
    ["1945", "14.055", "CW", "W0FGH", "5NN", "CO"],
    ["8:00 PM", "14.060", "CW", "N6PQR", "5NN", "CA"],  # Duplicate: N6PQR on 20m
]

for i, contact in enumerate(contacts, start=2):
    ws[f'A{i}'] = contact[0]
    ws[f'B{i}'] = contact[1]
    ws[f'C{i}'] = contact[2]
    ws[f'D{i}'] = contact[3]
    ws[f'E{i}'] = contact[4]
    ws[f'F{i}'] = contact[5]

wb.save(sys.argv[1])
print(f"Field Day raw log created: {sys.argv[1]}")
print(f"Total contacts: {len(contacts)}")
PYEOF

chmod +x /tmp/create_ham_log.py
python3 /tmp/create_ham_log.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Raw log spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_ham_log_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_ham_log_task.log || true
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

echo "=== Ham Radio Contest Log Task Setup Complete ==="
echo "📻 ARRL Field Day Log Organization Task"
echo ""
echo "📝 Your task:"
echo "  1. Standardize Time column (A): Convert all to 24-hour HH:MM format"
echo "     Examples: '2:30 PM' → '14:30', '1530' → '15:30'"
echo ""
echo "  2. Standardize Frequency column (B): Convert all to MHz decimal"
echo "     Examples: '14250 kHz' → '14.250', '7.185 MHz' → '7.185'"
echo ""
echo "  3. Standardize Mode column (C): Convert USB/LSB to SSB, keep CW/FT8"
echo ""
echo "  4. Add column G header 'Band': Derive from frequency"
echo "     7.0-7.3 MHz = '40m', 14.0-14.35 MHz = '20m', 21.0-21.45 MHz = '15m'"
echo ""
echo "  5. Add column H header 'Points': Use formula"
echo "     IF mode is 'CW' or 'FT8' then 2, else 1"
echo ""
echo "  6. Add column I header 'Duplicate': Mark duplicates"
echo "     If same callsign appears earlier on same band, mark 'DUP'"
echo ""
echo "  7. Create summary section starting at row 28:"
echo "     - Total Contacts: count all contacts"
echo "     - Valid Contacts: count non-duplicates"
echo "     - Total Points: sum of points for valid contacts"
echo ""
echo "  8. Save as: /home/ga/Documents/Spreadsheets/fieldday_score.xlsx"
echo ""
echo "💡 Tips:"
echo "  - Use formulas for Band, Points, and Duplicate columns"
echo "  - Band formula example: =IF(B2<7.5,\"40m\",IF(B2<20,\"20m\",\"15m\"))"
echo "  - Points formula example: =IF(OR(C2=\"CW\",C2=\"FT8\"),2,1)"
echo "  - Duplicate detection may need COUNTIFS to check callsign+band"
echo "  - Expected: 3 duplicates (K4ABC, W4JKL, N6PQR on same bands)"
echo "  - Expected score: ~38-40 points (24 contacts - 3 dups = 21 valid)"