#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Band Chord Chart Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directories
SPREADSHEET_DIR="/home/ga/Documents/Spreadsheets"
DOCS_DIR="/home/ga/Documents"
sudo -u ga mkdir -p "$SPREADSHEET_DIR"
sudo -u ga mkdir -p "$DOCS_DIR"

# Create the chord reference text file
CHORD_REF_PATH="$DOCS_DIR/chord_reference.txt"

cat > "$CHORD_REF_PATH" << 'EOF'
AUTUMN BREEZE - Lead Sheet Chord Progression
==============================================

This is a 16-bar jazz-fusion progression for your band rehearsal.
Simplify extended chords for rhythm section readability.

Measure 1-4:  Cmaj9  |  Dm7   |  G7sus  |  Cmaj7
Measure 5-8:  Am7    |  Dm7   |  G7     |  C6/9
Measure 9-12: Fmaj7  |  Bm7b5 |  E7b9   |  Am7
Measure 13-16: Dm7   |  G7    |  Cmaj7  |  Cmaj7

Instructions for creating band chord chart:
--------------------------------------------
- Create a 4×4 grid (4 measures per row, 4 rows total)
- Simplify chord extensions for readability:
  * Cmaj9 → C, Cmaj7 → C, C6/9 → C
  * Am7 → Am, Dm7 → Dm
  * G7sus → G7, E7b9 → E7
  * Fmaj7 → F
  * Bm7b5 can stay as-is or simplify to Bm
- Format for music stand distance (bold, 16pt font, centered)
- Add measure labels in first column

Expected simplified chart structure:
Row 1: Measures 1-4   | C  | Dm | G7 | C
Row 2: Measures 5-8   | Am | Dm | G7 | C  
Row 3: Measures 9-12  | F  | Bm7b5 | E7 | Am
Row 4: Measures 13-16 | Dm | G7 | C  | C
EOF

chown ga:ga "$CHORD_REF_PATH"
echo "✅ Chord reference created at: $CHORD_REF_PATH"

# Create an initial blank spreadsheet
SHEET_PATH="$SPREADSHEET_DIR/autumn_breeze_chart.xlsx"

cat > /tmp/create_chart.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Chord Chart"

# Add a title
ws['A1'] = "Autumn Breeze - Chord Chart"
ws['A1'].font = Font(bold=True, size=14)

# Add instruction
ws['A2'] = "Create a 4×4 grid below with simplified chords from chord_reference.txt"
ws['A2'].font = Font(size=10, italic=True)

# Leave rest blank for user to fill

wb.save(sys.argv[1])
print(f"Blank chord chart created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_chart.py
python3 /tmp/create_chart.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_chord_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_chord_task.log || true
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

echo "=== Band Chord Chart Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Read chord progression from: $CHORD_REF_PATH"
echo "  2. Create a 4×4 grid structure (4 measures per row, 4 rows)"
echo "  3. Simplify complex chords:"
echo "     - Cmaj9 → C, Cmaj7 → C, C6/9 → C"
echo "     - Am7 → Am, Dm7 → Dm"
echo "     - G7sus → G7, E7b9 → E7"
echo "     - Fmaj7 → F"
echo "     - Keep Bm7b5 as-is or simplify to Bm"
echo "  4. Format chords: bold, 16pt font, centered"
echo "  5. Add measure labels in first column"
echo "  6. Save the spreadsheet (Ctrl+S)"
echo ""
echo "Expected grid (simplified):"
echo "  Row 1: 1-4   | C  | Dm | G7 | C"
echo "  Row 2: 5-8   | Am | Dm | G7 | C"
echo "  Row 3: 9-12  | F  | Bm7b5 | E7 | Am"
echo "  Row 4: 13-16 | Dm | G7 | C  | C"