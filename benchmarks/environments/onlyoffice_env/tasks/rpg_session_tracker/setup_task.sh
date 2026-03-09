#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up RPG Session Tracker Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create a blank spreadsheet as starting point
SHEET_PATH="$WORKSPACE_DIR/dragon_hoard_loot.xlsx"

cat > /tmp/create_blank_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

# Create a completely blank workbook
wb = Workbook()
ws = wb.active
ws.title = "Sheet1"

# Just save the blank workbook
wb.save(sys.argv[1])
print(f"Blank spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_blank_sheet.py
python3 /tmp/create_blank_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_rpg_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_rpg_task.log || true
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

echo "=== RPG Session Tracker Task Setup Complete ==="
echo ""
echo "📋 SCENARIO: D&D Session Documentation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "You're the Dungeon Master. Last night's session ended with the party"
echo "defeating a dragon and looting its hoard. You scribbled notes on napkins,"
echo "but now need a clean digital record before Sunday's session."
echo ""
echo "📝 REQUIRED TASKS:"
echo ""
echo "1️⃣  CREATE CHARACTER TRACKING TABLE with these columns:"
echo "   • Character Name"
echo "   • Player Name"
echo "   • Previous Gold (GP)"
echo "   • Gold Gained"
echo "   • Total Gold (FORMULA: Previous + Gained)"
echo "   • Previous XP"
echo "   • XP Gained"
echo "   • Total XP (FORMULA: Previous + Gained)"
echo "   • Level Up? (FORMULA: IF Total XP >= 14000 then 'YES' else 'NO')"
echo ""
echo "2️⃣  ENTER CHARACTER DATA (4 party members):"
echo "   ┌─────────────────────────────────────────────────────────────┐"
echo "   │ Alaric    (Sarah)  │ 1,247 GP → +850  │ 11,300 XP → +2,100 │"
echo "   │ Thorgrim  (Marcus) │ 1,180 GP → +600  │ 11,850 XP → +1,050 │"
echo "   │ Elara     (Jen)    │ 1,390 GP → +1,100│ 12,100 XP → +2,100 │"
echo "   │ Krrosh    (David)  │   998 GP → +950  │ 10,900 XP → +2,100 │"
echo "   └─────────────────────────────────────────────────────────────┘"
echo ""
echo "3️⃣  CREATE MAGIC ITEMS SECTION (below character table):"
echo "   Add header: 'Magic Items Acquired'"
echo "   Create 2-column table: Item Name | Assigned To"
echo "   ┌──────────────────────────────────┬────────────┐"
echo "   │ Flaming Longsword                │ Alaric     │"
echo "   │ Cloak of Displacement            │ Elara      │"
echo "   │ Ring of Fire Resistance          │ Thorgrim   │"
echo "   │ Potion of Greater Healing (×3)   │ Party Pool │"
echo "   └──────────────────────────────────┴────────────┘"
echo ""
echo "4️⃣  FORMAT FOR READABILITY:"
echo "   • Bold all header rows"
echo "   • Use comma separators for gold (e.g., '1,247' not '1247')"
echo "   • Highlight or format 'YES' in Level Up column (optional)"
echo ""
echo "5️⃣  SAVE the file (Ctrl+S)"
echo ""
echo "💡 HINTS:"
echo "   • Level Up threshold is 14,000 Total XP"
echo "   • Thorgrim was absent (half XP/gold)"
echo "   • Only Elara should level up (12,100 + 2,100 = 14,200)"
echo "   • Use formulas, not hard-coded values for Totals and Level Up"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"