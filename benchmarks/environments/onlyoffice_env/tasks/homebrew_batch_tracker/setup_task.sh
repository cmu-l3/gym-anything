#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Homebrew Batch Tracker Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directories
DOCS_DIR="/home/ga/Documents"
SHEET_DIR="$DOCS_DIR/Spreadsheets"
sudo -u ga mkdir -p "$DOCS_DIR"
sudo -u ga mkdir -p "$SHEET_DIR"

# Create the brewing notes text file that the agent needs to transcribe
NOTES_PATH="$DOCS_DIR/brewing_notes.txt"

cat > "$NOTES_PATH" << 'EOF'
=================================================
HOMEBREW FERMENTATION LOG - TRANSCRIPTION NEEDED
=================================================

Batch Information:
------------------
Batch Name: Amber Ale Batch #1
Brew Date: March 15, 2024
Recipe: American Amber Ale (5 gallon batch)

Target Specifications:
----------------------
Target ABV: 5.2%
Target Fermentation Temperature Range: 66-72°F

Gravity Measurements:
---------------------
Original Gravity (Day 1, March 15): 1.052
Final Gravity (Day 12, March 26): 1.012

Note: Gravity readings only taken on brew day and final day
(standard practice for simple batches)

Daily Temperature Log:
----------------------
Day 1  - March 15, 2024 - 68°F
Day 2  - March 16, 2024 - 70°F  
Day 3  - March 17, 2024 - 71°F
Day 4  - March 18, 2024 - 70°F
Day 5  - March 19, 2024 - 69°F
Day 6  - March 20, 2024 - 68°F
Day 7  - March 21, 2024 - 67°F
Day 8  - March 22, 2024 - 67°F
Day 9  - March 23, 2024 - 68°F
Day 10 - March 24, 2024 - 69°F
Day 11 - March 25, 2024 - 68°F
Day 12 - March 26, 2024 - 67°F

=================================================
SPREADSHEET REQUIREMENTS:
=================================================

Required Structure:
-------------------
1. Batch metadata section (rows 1-2):
   - Cell A1: "Batch Name"    Cell B1: "Amber Ale Batch #1"
   - Cell A2: "Brew Date"     Cell B2: "3/15/2024"

2. Data table section (starting row 4):
   - Headers in row 4: Day | Date | Temp (°F) | Specific Gravity
   - Data rows 5-16: Daily readings for 12 days

3. Calculation section (starting row 1, columns F-G):
   - Original Gravity (reference to Day 1 gravity)
   - Final Gravity (reference to Day 12 gravity)  
   - Calculated ABV using formula: (OG - FG) × 131.25
   - Target ABV: 5.2

4. Temperature analysis (rows 6-8, columns F-G):
   - Min Fermentation Temp (MIN formula)
   - Max Fermentation Temp (MAX formula)
   - Avg Fermentation Temp (AVERAGE formula)

5. Quality assessment (rows 10-11, columns F-G):
   - ABV Target Met? (IF formula checking if within ±0.3%)
   - Temp Range OK? (IF with AND formula checking 66-72°F range)

Important Formulas:
-------------------
- ABV Calculation: =(OG_cell - FG_cell) * 131.25
  Where OG and FG are cell references to gravity values
  
- Temperature stats: Use MIN(), MAX(), AVERAGE() on temp column

- Quality checks:
  * ABV: =IF(ABS(calculated_ABV - target_ABV) < 0.3, "Yes", "No")
  * Temp: =IF(AND(min_temp >= 66, max_temp <= 72), "Yes", "No")

=================================================
EOF

chown ga:ga "$NOTES_PATH"
echo "✅ Brewing notes created at: $NOTES_PATH"

# Create an empty starter spreadsheet (agent will populate it)
SHEET_PATH="$SHEET_DIR/brewing_log.xlsx"

cat > /tmp/create_brewing_starter.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

# Create a blank workbook with just Sheet1
wb = Workbook()
ws = wb.active
ws.title = "Fermentation Log"

# Just save empty - agent needs to fill everything
wb.save(sys.argv[1])
print(f"Starter spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_brewing_starter.py
python3 /tmp/create_brewing_starter.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Starter spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the empty spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_brewing_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_brewing_task.log || true
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

echo "=== Homebrew Batch Tracker Task Setup Complete ==="
echo ""
echo "📋 TASK OVERVIEW:"
echo "════════════════════════════════════════════════════════"
echo "You are helping homebrewer Alex digitize fermentation data"
echo "from a notebook into a spreadsheet for the brewing club."
echo ""
echo "📄 Source Data: /home/ga/Documents/brewing_notes.txt"
echo "💾 Save As: /home/ga/Documents/Spreadsheets/brewing_log.xlsx"
echo ""
echo "✅ REQUIRED SECTIONS:"
echo "════════════════════════════════════════════════════════"
echo ""
echo "1️⃣  BATCH METADATA (A1:B2):"
echo "   A1: Batch Name      B1: Amber Ale Batch #1"
echo "   A2: Brew Date       B2: 3/15/2024"
echo ""
echo "2️⃣  DATA TABLE (A4:D16):"
echo "   Headers (Row 4): Day | Date | Temp (°F) | Specific Gravity"
echo "   Rows 5-16: 12 days of fermentation data"
echo "   - OG (1.052) in D5, FG (1.012) in D16"
echo "   - Temperatures for all 12 days in column C"
echo ""
echo "3️⃣  CALCULATIONS (F1:G4):"
echo "   F1: Original Gravity (OG)    G1: =D5"
echo "   F2: Final Gravity (FG)       G2: =D16"
echo "   F3: Calculated ABV (%)       G3: =(G1-G2)*131.25"
echo "   F4: Target ABV (%)           G4: 5.2"
echo ""
echo "4️⃣  TEMPERATURE STATS (F6:G8):"
echo "   F6: Min Fermentation Temp    G6: =MIN(C5:C16)"
echo "   F7: Max Fermentation Temp    G7: =MAX(C5:C16)"
echo "   F8: Avg Fermentation Temp    G8: =AVERAGE(C5:C16)"
echo ""
echo "5️⃣  QUALITY CHECKS (F10:G11):"
echo "   F10: ABV Target Met?         G10: =IF(ABS(G3-G4)<0.3,\"Yes\",\"No\")"
echo "   F11: Temp Range OK?          G11: =IF(AND(G6>=66,G7<=72),\"Yes\",\"No\")"
echo ""
echo "💡 TIPS:"
echo "════════════════════════════════════════════════════════"
echo "- Read brewing_notes.txt carefully for all data"
echo "- Use FORMULAS (not calculated values) for all computations"
echo "- Expected ABV result: ~5.25%"
echo "- All temps should be between 67-71°F"
echo "- Save with Ctrl+S when complete"
echo ""