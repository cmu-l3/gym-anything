#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Seed Inventory Spring Exchange Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create a blank spreadsheet
SHEET_PATH="$WORKSPACE_DIR/seed_exchange_inventory.xlsx"

cat > /tmp/create_blank_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

wb = Workbook()
ws = wb.active
ws.title = "Sheet1"

# Create completely blank spreadsheet
# The agent needs to add all headers and data

wb.save(sys.argv[1])
print(f"Blank spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_blank_sheet.py
python3 /tmp/create_blank_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_seed_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_seed_task.log || true
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

echo "=== Seed Inventory Spring Exchange Task Setup Complete ==="
echo "📝 Instructions:"
echo "  Create a seed inventory spreadsheet for a spring exchange event."
echo ""
echo "  Row 1 (Headers):"
echo "    A1: Variety Name"
echo "    B1: Plant Type"
echo "    C1: Seeds Available"
echo "    D1: Year Saved"
echo "    E1: Germination Notes"
echo ""
echo "  Row 2: Brandywine Tomato | Tomato | 45 | 2024 | Good germination last year"
echo "  Row 3: Detroit Dark Red Beet | Beet | 30 | 2023 | Older seeds - test before trading"
echo "  Row 4: Scarlet Nantes Carrot | Carrot | 60 | 2024 | Fresh seeds, high confidence"
echo ""
echo "  Save the spreadsheet (Ctrl+S)"
echo ""
echo "Context: You're preparing for a spring seed exchange event. This inventory"
echo "helps track what seeds you have available for trading with other gardeners."