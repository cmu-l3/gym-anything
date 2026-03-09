#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Sleep Optimization Experiment Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the raw data text file
RAW_DATA_PATH="$WORKSPACE_DIR/sleep_experiment_raw.txt"

cat > "$RAW_DATA_PATH" << 'RAWEOF'
Sleep Experiment - January 2025
================================

Background: Alex (32, software developer) has been exhausted despite 7-8 hours of sleep.
After falling asleep in a meeting, Alex decided to systematically test different strategies.

Tested Strategies:
- Strategy A: No screens 2 hours before bed
- Strategy B: Chamomile tea at 9 PM
- Strategy C: Room temperature set to 65°F (normally 70°F)
- Strategy D: 10-minute meditation before bed

Results (2 weeks):

Night 1 (Jan 6): Strategy A only | Sleep Quality: 6/10 | Times Woken: 2
Night 2 (Jan 7): Strategy B only | Sleep Quality: 5/10 | Times Woken: 3
Night 3 (Jan 8): Strategy C only | Sleep Quality: 8/10 | Times Woken: 1
Night 4 (Jan 9): Strategy D only | Sleep Quality: 7/10 | Times Woken: 1
Night 5 (Jan 10): Strategies A+B | Sleep Quality: 6/10 | Times Woken: 2
Night 6 (Jan 11): Strategies A+C | Sleep Quality: 9/10 | Times Woken: 0
Night 7 (Jan 12): Strategies B+C | Sleep Quality: 7/10 | Times Woken: 1
Night 8 (Jan 13): Strategies C+D | Sleep Quality: 8/10 | Times Woken: 1
Night 9 (Jan 14): No strategies (control) | Sleep Quality: 4/10 | Times Woken: 4
Night 10 (Jan 15): Strategy A only | Sleep Quality: 6/10 | Times Woken: 2
Night 11 (Jan 16): Strategy C only | Sleep Quality: 9/10 | Times Woken: 0
Night 12 (Jan 17): Strategy D only | Sleep Quality: 6/10 | Times Woken: 2
Night 13 (Jan 18): DATA MISSING (forgot to log after late party)
Night 14 (Jan 19): Strategies A+C+D | Sleep Quality: 8/10 | Times Woken: 1

Notes:
- Night 13 data is missing - Alex forgot to log after a party
- Some nights combined multiple strategies to test interactions
- Sleep quality is subjective (1-10 scale, rated each morning)
- Times woken is objective count during the night
- Goal: Identify which single strategy has highest impact for doctor appointment

Task: Create a structured spreadsheet to analyze this data and identify the best strategy.
RAWEOF

chown ga:ga "$RAW_DATA_PATH"

echo "✅ Raw data file created at: $RAW_DATA_PATH"

# Create a blank starter spreadsheet (optional - agent could create from scratch)
# But let's create one to make the task slightly easier
SHEET_PATH="$WORKSPACE_DIR/sleep_analysis_complete.xlsx"

cat > /tmp/create_sleep_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

wb = Workbook()
ws = wb.active
ws.title = "Sheet1"

# Just create a blank workbook - agent will create sheets
ws['A1'] = "Sleep Analysis Worksheet"
ws['A2'] = "Read the instructions in /home/ga/Documents/Spreadsheets/sleep_experiment_raw.txt"

wb.save(sys.argv[1])
print(f"Blank spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_sleep_sheet.py
python3 /tmp/create_sleep_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_sleep_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_sleep_task.log || true
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

echo "=== Sleep Optimization Experiment Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "  Alex (software developer) has been exhausted and tested 4 sleep strategies"
echo "  over 14 nights. Raw data is in: sleep_experiment_raw.txt"
echo ""
echo "📝 YOUR TASK:"
echo "  1. Read the raw data file to understand the experiment"
echo "  2. Create TWO sheets in this spreadsheet:"
echo ""
echo "  SHEET 1 - 'Raw_Data':"
echo "    • Structure the 14 nights of data into columns:"
echo "      - Night # (1-14)"
echo "      - Date (Jan 6-19)"
echo "      - Strategy A Used (Yes/No or 1/0)"
echo "      - Strategy B Used (Yes/No or 1/0)"
echo "      - Strategy C Used (Yes/No or 1/0)"
echo "      - Strategy D Used (Yes/No or 1/0)"
echo "      - Sleep Quality (1-10)"
echo "      - Times Woken"
echo "    • Night 13 has missing data - leave blank or mark N/A"
echo "    • Make headers BOLD"
echo "    • Apply conditional formatting to Sleep Quality:"
echo "      - GREEN background for values ≥8"
echo "      - RED background for values ≤5"
echo ""
echo "  SHEET 2 - 'Analysis':"
echo "    • Create a summary table with:"
echo "      - Strategy name (A, B, C, D)"
echo "      - Average sleep quality when used (use FORMULAS like AVERAGEIF)"
echo "      - Average times woken when used"
echo "      - Count of nights tested"
echo "    • Identify and highlight the BEST strategy:"
echo "      - Cell labeled 'BEST SINGLE STRATEGY:' with the letter"
echo "      - Highlight this cell with YELLOW background"
echo "    • Identify worst night:"
echo "      - Cell labeled 'WORST NIGHT:' with the date"
echo ""
echo "  3. Save the file (Ctrl+S)"
echo ""
echo "💡 HINTS:"
echo "  - Night 3 & 11: Strategy C only, quality 8 & 9 → C seems effective"
echo "  - Night 9: No strategies (control), quality 4 → worst night"
echo "  - Use AVERAGEIF to calculate avg quality when Strategy X was used"
echo "  - Strategy C appears in nights: 3, 6, 7, 8, 11, 14"
echo ""
echo "Expected outcome: Strategy C should have highest average (~8.2)"