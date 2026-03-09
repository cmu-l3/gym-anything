#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Artifact Catalog Completion Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets/archaeology_survey"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create field notes file
NOTES_FILE="$WORKSPACE_DIR/field_notes.txt"

cat > "$NOTES_FILE" << 'EOF'
ARTIFACT FIELD NOTES - CA-YOL-42 Survey - June 15, 2024
Archaeologist: Dr. Sarah Martinez
Weather: Partly cloudy, good visibility

GRID SQUARE: NE
001 - ceramic sherd, decorated rim, likely indigenous, found 15cm depth, good cond
002 - obsidian flake, black, sharp edges, 8cm depth, excellent
003 - bone fragment, possibly deer, weathered, surface find, poor condition
004 - glass fragment (modern intrusion - probably 1950s bottle), green, surface, exclude from analysis
005 - ceramic sherd, body fragment, same vessel as 001?, 14cm depth, fair cond

GRID SQUARE: SW  
001 - projectile point, obsidian, complete, 22cm depth, EXCELLENT - photograph before transport
002 - grinding stone fragment, basalt, worn surface visible, 10cm depth, fair condition
003 - charcoal sample (send for C14 dating), from fire feature, 25cm depth, bag #SW-03-CHAR

GRID SQUARE: NW
001 - ceramic sherd, plain body, different clay from NE finds, 18cm depth, good
002 - shell bead, marine species (possibly Olivella), 12cm depth, good - RARE for this site
003 - another obsidian flake, similar to NE-002, 9cm depth, good condition
004 - bone awl or tool fragment, worked bone confirmed, 20cm depth, fair cond
005 - ceramic sherd, rim fragment with handles(?), unusual form, 16cm, good - needs specialist analysis
006 - stone tool fragment, basalt, broken, function unclear, 11cm, fair

Note: All depths measured from modern surface. Grid datum points confirmed with GPS.
Modern glass in NE excluded from catalog count - contamination.
Total artifacts to catalog: 14 (excluding modern intrusion)
EOF

chown ga:ga "$NOTES_FILE"

echo "✅ Field notes created at: $NOTES_FILE"

# Create the catalog template spreadsheet with example entries
SHEET_PATH="$WORKSPACE_DIR/artifact_catalog.xlsx"

cat > /tmp/create_catalog_template.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter
import sys

wb = Workbook()
ws = wb.active
ws.title = "Artifact Catalog"

# Headers
headers = ["Catalog ID", "Grid Square", "Item Number", "Category", "Material", "Depth (cm)", "Condition", "Notes"]
ws.append(headers)

# Style headers
header_fill = PatternFill(start_color="366092", end_color="366092", fill_type="solid")
header_font = Font(color="FFFFFF", bold=True, size=11)
border = Border(
    left=Side(style='thin'),
    right=Side(style='thin'),
    top=Side(style='thin'),
    bottom=Side(style='thin')
)

for col_num, header in enumerate(headers, 1):
    cell = ws.cell(row=1, column=col_num)
    cell.fill = header_fill
    cell.font = header_font
    cell.alignment = Alignment(horizontal="center", vertical="center")
    cell.border = border

# Set column widths
ws.column_dimensions['A'].width = 20
ws.column_dimensions['B'].width = 12
ws.column_dimensions['C'].width = 12
ws.column_dimensions['D'].width = 15
ws.column_dimensions['E'].width = 12
ws.column_dimensions['F'].width = 12
ws.column_dimensions['G'].width = 12
ws.column_dimensions['H'].width = 45

# Add example entries (first 4 items from NE grid as completed examples)
# These show the correct format the agent should follow
example_data = [
    ["CA-YOL-42-NE-001", "NE", "001", "Ceramic", "Clay", 15, "Good", "Decorated rim fragment, indigenous origin"],
    ["CA-YOL-42-NE-002", "NE", "002", "Lithic", "Obsidian", 8, "Excellent", "Flake, black obsidian, sharp edges"],
    ["CA-YOL-42-NE-003", "NE", "003", "Faunal", "Bone", 0, "Poor", "Bone fragment, possibly deer, weathered, surface find"],
    ["CA-YOL-42-NE-005", "NE", "005", "Ceramic", "Clay", 14, "Fair", "Body fragment, possibly same vessel as 001"],
    ["", "", "", "", "", "", "", ""],  # Empty row for spacing
]

for row_data in example_data:
    ws.append(row_data)

# Add instruction notes below the data
ws['A10'] = "INSTRUCTIONS:"
ws['A10'].font = Font(bold=True, size=10, color="8B0000")

ws['A11'] = "Complete catalog for remaining artifacts from field_notes.txt"
ws['A11'].font = Font(italic=True, size=9)

ws['A12'] = "Format: CA-YOL-42-[GRID]-[NUMBER] (use grid codes NE, SW, NW)"
ws['A12'].font = Font(italic=True, size=9)

ws['A13'] = "Categories: Ceramic, Lithic, Faunal, Shell, Charcoal"
ws['A13'].font = Font(italic=True, size=9)

ws['A14'] = "EXCLUDE: Modern glass (item NE-004) - contamination, not archaeological"
ws['A14'].font = Font(italic=True, size=9, color="FF0000")

ws['A15'] = "Total to catalog: 14 artifacts"
ws['A15'].font = Font(bold=True, size=9)

# Freeze top row
ws.freeze_panes = 'A2'

wb.save(sys.argv[1])
print(f"Catalog template created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_catalog_template.py
python3 /tmp/create_catalog_template.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Catalog template created at: $SHEET_PATH"

# Launch ONLYOFFICE Spreadsheet with the catalog
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_archaeology_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_archaeology_task.log || true
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

echo "=== Artifact Catalog Task Setup Complete ==="
echo ""
echo "📝 SCENARIO:"
echo "  You're helping finish an archaeological catalog. The archaeologist had to leave"
echo "  early and needs this completed by Monday for the university lab."
echo ""
echo "📋 TASK:"
echo "  1. Open field_notes.txt (in same folder) to see the raw field notes"
echo "  2. Complete the artifact catalog following the format shown in rows 2-5"
echo "  3. Catalog all 14 artifacts across 3 grid squares (NE, SW, NW)"
echo "  4. EXCLUDE the modern glass (NE-004) - it's contamination, not archaeological"
echo "  5. Use Catalog ID format: CA-YOL-42-[GRID]-[NUMBER]"
echo "  6. Use standardized categories: Ceramic, Lithic, Faunal, Shell, Charcoal"
echo "  7. Fill all required fields: Grid, Item Number, Category, Material, Depth, Condition, Notes"
echo "  8. Save the spreadsheet (Ctrl+S)"
echo ""
echo "Expected distribution: NE=4, SW=3, NW=6 (14 total)"