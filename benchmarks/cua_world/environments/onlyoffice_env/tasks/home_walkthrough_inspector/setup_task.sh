#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Home Walkthrough Inspector Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Define the file path where the agent should save the spreadsheet
SHEET_PATH="$WORKSPACE_DIR/home_inspection_walkthrough.xlsx"

# Remove any existing file to ensure fresh start
rm -f "$SHEET_PATH"

echo "📋 Task Context: Home Inspection Walkthrough Documentation"
echo "   Scenario: First-time homebuyers viewing a 1960s ranch house"
echo "   Listed at: \$385,000 | Budget buffer for repairs: \$15,000"
echo ""

# Launch ONLYOFFICE Spreadsheet Editor with blank workbook
echo "Launching ONLYOFFICE Spreadsheet Editor with blank workbook..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors --new:spreadsheet > /tmp/onlyoffice_home_inspection_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 25; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_home_inspection_task.log || true
    # Don't exit - agent might still be able to complete task
fi

# Wait for window to appear
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "WARNING: ONLYOFFICE window did not appear within timeout"
    # Don't exit - window might appear later
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center of screen to ensure correct desktop focus
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

sleep 2

echo "=== Home Walkthrough Inspector Task Setup Complete ==="
echo ""
echo "📝 TASK INSTRUCTIONS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "CONTEXT: You're helping a first-time homebuyer create a systematic home"
echo "inspection worksheet. They're viewing a 1960s ranch house listed at \$385,000"
echo "and need to document potential issues observed during their walkthrough."
echo "They have a \$15,000 budget buffer for repairs."
echo ""
echo "CREATE A SPREADSHEET WITH THE FOLLOWING STRUCTURE:"
echo ""
echo "1. COLUMN HEADERS (Row 1):"
echo "   A1: Room/Area"
echo "   B1: Issue Observed"
echo "   C1: Severity"
echo "   D1: Est. Min Cost"
echo "   E1: Est. Max Cost"
echo ""
echo "2. ENTER THESE 8 FINDINGS (Rows 2-9):"
echo ""
echo "   Row 2: Living Room | Water stains on ceiling, musty smell | Major | 1500 | 4000"
echo "   Row 3: Kitchen | Dishwasher doesn't drain, standing water | Moderate | 150 | 800"
echo "   Row 4: Master Bath | Cracked tile, soft floor near toilet | Major | 800 | 3500"
echo "   Row 5: Basement | Visible foundation crack, 4ft long | Major | 2000 | 8000"
echo "   Row 6: Roof (Exterior) | Missing/damaged shingles visible | Moderate | 400 | 1200"
echo "   Row 7: Electrical Panel | Only 100amp service, rust on panel | Moderate | 1200 | 3000"
echo "   Row 8: HVAC | Furnace dated 1998, loud operation | Major | 3000 | 6000"
echo "   Row 9: Windows | 6 windows have broken seals (foggy) | Minor | 900 | 1800"
echo ""
echo "3. CREATE SUMMARY SECTION (Starting at Row 11):"
echo ""
echo "   A11: TOTAL REPAIR COST RANGE:"
echo "   D11: =SUM(D2:D9)    [Formula to sum minimum costs]"
echo "   E11: =SUM(E2:E9)    [Formula to sum maximum costs]"
echo ""
echo "   A12: Your Budget Buffer:"
echo "   D12: 15000"
echo "   E12: 15000"
echo ""
echo "   A13: Over/Under Budget:"
echo "   D13: =D12-D11    [Formula: budget minus min costs]"
echo "   E13: =E12-E11    [Formula: budget minus max costs]"
echo ""
echo "4. FORMATTING:"
echo "   - Make header row (Row 1) BOLD"
echo "   - Format cost columns (D and E) as CURRENCY (with dollar signs)"
echo "   - Make summary labels (A11, A12, A13) BOLD"
echo "   - Make total cost row (Row 11) BOLD or visually distinct"
echo ""
echo "5. SAVE THE FILE:"
echo "   - Save as: home_inspection_walkthrough.xlsx"
echo "   - Location: /home/ga/Documents/Spreadsheets/"
echo "   - Use Ctrl+S to save"
echo ""
echo "EXPECTED CALCULATIONS:"
echo "   - Total Min Cost: \$9,950"
echo "   - Total Max Cost: \$28,300"
echo "   - Budget vs Min: +\$5,050 (under budget)"
echo "   - Budget vs Max: -\$13,300 (over budget)"
echo ""
echo "This helps the buyer see if worst-case repair costs exceed their budget!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"