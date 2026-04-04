#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Dinner Party Allergy Matrix Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/party_planning"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the input data file with messy allergy information
INPUT_FILE="$WORKSPACE_DIR/guest_allergies.txt"

cat > "$INPUT_FILE" << 'EOF'
DINNER PARTY GUEST ALLERGIES - Tomorrow night!

Guests confirmed (6 people):

Sarah - can't have gluten (celiac)
Mike - allergic to shellfish
Jennifer - lactose intolerant (no dairy)
David - tree nut allergy
Emma - dairy allergy AND nut allergy (both!)
Tom - no allergies

Planned Menu (5 dishes):

1. Caprese Salad - tomatoes, fresh mozzarella, basil, balsamic
2. Grilled Salmon - with lemon and herbs
3. Mushroom Risotto - arborio rice, mushrooms, parmesan, white wine
4. Chocolate Cake - flour, eggs, butter, chocolate
5. Fruit Platter - mixed berries, melon, garnished with sliced almonds

HELP! Need to figure out who can eat what before tomorrow!
EOF

chown ga:ga "$INPUT_FILE"

echo "✅ Input data created at: $INPUT_FILE"
echo "Contents:"
cat "$INPUT_FILE"
echo ""

# Create a starter spreadsheet to guide the user
SHEET_PATH="$WORKSPACE_DIR/allergy_matrix.xlsx"

cat > /tmp/create_starter_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Allergy Matrix"

# Add instructions at the top
ws['A1'] = "DINNER PARTY ALLERGY SAFETY MATRIX"
ws['A1'].font = Font(bold=True, size=14)
ws['A2'] = "Create a cross-reference showing which dishes are safe for each guest"
ws['A3'] = "Input data: /home/ga/Documents/party_planning/guest_allergies.txt"
ws['A4'] = ""

# Add hints
ws['A5'] = "Suggested approach:"
ws['A6'] = "- List guests in rows (or columns)"
ws['A7'] = "- List dishes in columns (or rows)"
ws['A8'] = "- Mark each cell as SAFE or UNSAFE"
ws['A9'] = "- Use colors (green=safe, red=unsafe) and/or symbols (✓/✗)"
ws['A10'] = "- Identify guests with limited safe options!"
ws['A11'] = ""

# Leave space for user to build matrix
ws['A12'] = "Start your matrix below:"

wb.save(sys.argv[1])
print(f"Starter spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_starter_sheet.py
python3 /tmp/create_starter_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Starter spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_allergy_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_allergy_task.log || true
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

echo "=== Dinner Party Allergy Matrix Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "  1. Review guest allergy info in: $INPUT_FILE"
echo "  2. Create a cross-reference matrix showing guests vs dishes"
echo "  3. Mark each guest-dish combination as SAFE or UNSAFE"
echo "  4. Use visual indicators (colors, symbols, or text)"
echo "  5. Identify guests with critically limited options (Emma!)"
echo "  6. Save the spreadsheet (Ctrl+S)"
echo ""
echo "💡 Quick Reference:"
echo "  Guests: Sarah (gluten), Mike (shellfish), Jennifer (dairy),"
echo "          David (nuts), Emma (dairy+nuts), Tom (none)"
echo "  Dishes: Caprese Salad, Grilled Salmon, Mushroom Risotto,"
echo "          Chocolate Cake, Fruit Platter"
echo ""
echo "⚠️  Critical: Emma has BOTH dairy and nut allergies!"