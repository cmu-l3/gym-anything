#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Family Archive Digitization Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directories
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
DOCS_DIR="/home/ga/Documents"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$DOCS_DIR"

# Create the catalog items reference file
CATALOG_ITEMS="$DOCS_DIR/catalog_items.txt"

cat > "$CATALOG_ITEMS" << 'CATALOGEOF'
FAMILY ARCHIVE DIGITIZATION BATCH #1 - Items to Catalog

1. Wedding photo of James & Martha, June 15, 1947, Riverside Church
   - Photo, B&W, 8x10 inches
   - Shows: James Henderson, Martha Henderson (née Wilson)
   - Condition: Good, slight yellowing at edges
   - Scanned file: henderson_wedding_1947.jpg (3.2 MB)
   - Physical location: Album 1, Page 3

2. Letter from Martha to her mother, postmarked August 3, 1948
   - Document, handwritten, 2 pages
   - Shows: Martha Henderson
   - Condition: Fair, fold lines weakening
   - Scanned file: martha_letter_1948_08.pdf (1.8 MB)
   - Physical location: Box 2, Folder "Correspondence 1940s"

3. Henderson family at beach, circa Summer 1952
   - Photo, Color, 4x6 inches
   - Shows: James Henderson, Martha Henderson, Robert Henderson (child), Susan Henderson (infant)
   - Condition: Poor - severe color fading, needs restoration
   - Scanned file: family_beach_1952.jpg (2.1 MB)
   - Physical location: Loose photos box

4. Robert's high school diploma, June 1969
   - Document, printed, certificate
   - Shows: Robert James Henderson
   - Condition: Excellent
   - Scanned file: robert_diploma_1969.pdf (4.5 MB)
   - Physical location: Box 3, Folder "Certificates"

5. Susan's wedding invitation, May 20, 1972
   - Document, printed
   - Shows: Susan Henderson, Michael Torres
   - Condition: Good
   - Scanned file: susan_wedding_invitation_1972.pdf (0.9 MB)
   - Physical location: Box 2, Folder "Correspondence 1970s"

6. Henderson family reunion, July 4, 1976
   - Photo, Color, 5x7 inches
   - Shows: James Henderson, Martha Henderson, Robert Henderson, Susan Torres, Michael Torres, various extended family (15+ people)
   - Condition: Fair, slight fading
   - Scanned file: reunion_1976.jpg (3.8 MB)
   - Physical location: Album 2, Page 12

7. Martha's recipe cards, circa 1950s-1980s
   - Document, handwritten, collection
   - Shows: Martha Henderson
   - Condition: Fair, staining from kitchen use
   - Scanned file: martha_recipes.pdf (2.7 MB)
   - Physical location: Box 4, Folder "Recipes"

8. James's military discharge papers, November 12, 1945
   - Document, printed, official
   - Shows: James Robert Henderson
   - Condition: Fair, foxing (brown spots) present - needs conservation
   - Scanned file: james_discharge_1945.pdf (1.5 MB)
   - Physical location: Box 3, Folder "Military"

9. Christmas photo, December 1958
   - Photo, B&W, 4x6 inches
   - Shows: James Henderson, Martha Henderson, Robert Henderson, Susan Henderson
   - Condition: Good
   - Scanned file: christmas_1958.jpg (2.3 MB)
   - Physical location: Album 1, Page 18

10. Property deed for 428 Maple Street, dated March 15, 1950
    - Document, printed, legal
    - Shows: James Henderson, Martha Henderson
    - Condition: Good, but fragile due to age
    - Scanned file: property_deed_1950.pdf (3.1 MB)
    - Physical location: Box 3, Folder "Property"

11. Robert's baby photo, circa 1950
    - Photo, B&W, 3x5 inches
    - Shows: Robert Henderson (infant)
    - Condition: Fair, crease across middle
    - Scanned file: robert_baby_1950.jpg (1.6 MB)
    - Physical location: Album 1, Page 5

12. Martha's obituary clipping, February 2003
    - Document, newsprint
    - Shows: Martha Wilson Henderson
    - Condition: Poor - newsprint degrading rapidly, URGENT conservation needed
    - Scanned file: martha_obituary_2003.pdf (0.8 MB)
    - Physical location: Box 2, Folder "Obituaries"
CATALOGEOF

chown ga:ga "$CATALOG_ITEMS"

echo "✅ Catalog items reference created at: $CATALOG_ITEMS"

# Create a blank spreadsheet to start with
SHEET_PATH="$WORKSPACE_DIR/family_archive_catalog.xlsx"

cat > /tmp/create_blank_catalog.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

wb = Workbook()
ws = wb.active
ws.title = "Archive Catalog"

# Start with a blank sheet - user needs to add headers and data
wb.save(sys.argv[1])
print(f"Blank catalog spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_blank_catalog.py
python3 /tmp/create_blank_catalog.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_archive_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_archive_task.log || true
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

echo "=== Family Archive Digitization Task Setup Complete ==="
echo ""
echo "📋 TASK INSTRUCTIONS:"
echo "════════════════════════════════════════════════════════════════"
echo "You are cataloging digitized family archive materials."
echo "Reference file: /home/ga/Documents/catalog_items.txt"
echo ""
echo "Required Spreadsheet Structure:"
echo "  1. Column Headers (Row 1):"
echo "     - Catalog_ID, Item_Type, Date, Description, People_Depicted"
echo "     - Physical_Condition, Conservation_Priority, Digital_Filename"
echo "     - File_Size_MB, Physical_Location"
echo ""
echo "  2. Data Entry (Rows 2-13): Enter all 12 items from reference file"
echo ""
echo "  3. Catalog ID Format: HEND-YYYY-### (e.g., HEND-1947-001)"
echo "     - Extract year from item date"
echo "     - Use sequential numbering within each year"
echo ""
echo "  4. Conservation Priority Logic:"
echo "     - Poor condition + urgent language → URGENT"
echo "     - Poor condition (no urgent) → High"
echo "     - Fair + conservation mention → High"
echo "     - Fair (no conservation) → Medium"
echo "     - Good or Excellent → Low"
echo ""
echo "  5. Apply conditional formatting to Conservation_Priority:"
echo "     - URGENT: Red background"
echo "     - High: Orange/yellow background"
echo ""
echo "  6. Summary Section (starting at row 15):"
echo "     - Total Items: (with count)"
echo "     - Total Digital Storage (MB): (with SUM formula)"
echo "     - Items Needing Urgent Conservation: (with COUNTIF formula)"
echo ""
echo "  7. Save the file (Ctrl+S)"
echo "════════════════════════════════════════════════════════════════"