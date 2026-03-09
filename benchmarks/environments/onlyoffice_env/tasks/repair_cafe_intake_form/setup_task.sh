#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Repair Café Intake Form Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the messy source document with inconsistent repair notes
DOC_PATH="$WORKSPACE_DIR/repair_notes_raw.docx"

cat > /tmp/create_messy_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt, RGBColor
import sys

doc = Document()

# Add a basic title
title = doc.add_paragraph("Repair Notes - Need Formatting for Grant Report")
title.runs[0].bold = True
title.runs[0].font.size = Pt(14)

doc.add_paragraph("")
doc.add_paragraph("These are rough notes from volunteers. Please format into standardized intake forms.")
doc.add_paragraph("")
doc.add_paragraph("=" * 60)
doc.add_paragraph("")

# Repair 1 - Relatively complete but inconsistent
doc.add_paragraph("Repair 1 - Toaster")
doc.add_paragraph("Date: March 15, 2024")
doc.add_paragraph("Customer: Sarah M.")
doc.add_paragraph("Problem: wouldn't heat up at all, no red glow")
doc.add_paragraph("Volunteer: Mike Chen")
doc.add_paragraph("What we found: heating element burned out, visible damage")
doc.add_paragraph("Result: FIXED - replaced heating element from parts bin")
doc.add_paragraph("Parts: heating element (had in stock)")
doc.add_paragraph("Time: about 25 minutes")
doc.add_paragraph("")

# Repair 2 - Text message style, incomplete
doc.add_paragraph("repair #2")
doc.add_paragraph("3/15/24 - laptop screen flickering")
doc.add_paragraph("Alex volunteer")
doc.add_paragraph("customer didnt leave name")
doc.add_paragraph("probs the display cable but we couldnt fix without replacement part")
doc.add_paragraph("outcome: not fixable (needs part we dont have)")
doc.add_paragraph("told them to order cable online, about $30")
doc.add_paragraph("45 min trying to diagnose")
doc.add_paragraph("")

# Repair 3 - Handwritten notes style, casual
doc.add_paragraph("Item 3: desk lamp")
doc.add_paragraph("Mar 16 2024")
doc.add_paragraph("Brought in by elderly gentleman (Mr. Rodriguez)")
doc.add_paragraph("Lamp wouldn't turn on - sentimental value, belonged to his father")
doc.add_paragraph("Tech: Jessica P. found loose wire at base")
doc.add_paragraph("Fixed by resoldering connection")
doc.add_paragraph("SUCCESS! Customer was very happy")
doc.add_paragraph("No parts needed")
doc.add_paragraph("Time spent: 20 mins")
doc.add_paragraph("")

# Repair 4 - Email fragment style
doc.add_paragraph("REPAIR ITEM #4")
doc.add_paragraph("Kitchen blender - Osterizer brand")
doc.add_paragraph("Date of repair: 3/16/2024")
doc.add_paragraph("Customer name: Jenny K.")
doc.add_paragraph("Issue reported: motor making grinding noise, only works sometimes")
doc.add_paragraph("Technician: Raj Patel")
doc.add_paragraph("Diagnosis: worn motor brushes causing intermittent contact")
doc.add_paragraph("Outcome: PARTIALLY FIXED - works on low speed only, high speed still problematic")
doc.add_paragraph("Parts used: cleaned and adjusted existing brushes (no replacement)")
doc.add_paragraph("Duration: 35 minutes")
doc.add_paragraph("")

# Repair 5 - Very casual, incomplete info
doc.add_paragraph("5th repair - iPhone 8")
doc.add_paragraph("march 17")
doc.add_paragraph("screen cracked badly")
doc.add_paragraph("teen customer, idk name")
doc.add_paragraph("Sam did the repair")
doc.add_paragraph("replaced screen with one we had")
doc.add_paragraph("worked perfectly after")
doc.add_paragraph("took like 30 min")
doc.add_paragraph("part from our inventory")
doc.add_paragraph("")

doc.add_paragraph("=" * 60)
doc.add_paragraph("")
doc.add_paragraph("END OF NOTES - Please convert to standardized intake forms!")

doc.save(sys.argv[1])
print(f"Messy repair notes document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_messy_doc.py
python3 /tmp/create_messy_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Source document created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_repair_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_repair_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Repair Café Intake Form Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Review the messy repair notes in the document"
echo "  2. Create a new standardized format with:"
echo "     - Document title: 'Repair Café Intake Forms' (with proper heading formatting)"
echo "     - 5 repair entries with consistent structure"
echo "     - Each entry should have:"
echo "       * Bold entry header (e.g., 'REPAIR #1')"
echo "       * Standardized field labels (bold): Date, Item Type, Customer Name, Problem Description,"
echo "         Volunteer Name, Diagnosis, Outcome, Parts Needed, Time Spent"
echo "       * Extract and organize information from the messy notes"
echo "  3. Clean up casual language (remove 'idk', 'probs', etc.)"
echo "  4. Ensure consistent spacing and formatting throughout"
echo "  5. Save as: /home/ga/Documents/TextDocuments/repair_intake_formatted.docx"
echo "     (Use Ctrl+Shift+S for Save As, or File > Save As)"
echo ""
echo "Expected structure for each repair:"
echo "  REPAIR #1 (bold)"
echo "  Date: [date] (label bold)"
echo "  Item Type: [item] (label bold)"
echo "  Customer Name: [name or Anonymous] (label bold)"
echo "  Problem Description: [description] (label bold)"
echo "  Volunteer Name: [name] (label bold)"
echo "  Diagnosis: [diagnosis] (label bold)"
echo "  Outcome: [Fixed/Partially Fixed/Not Fixable] (label bold)"
echo "  Parts Needed: [parts or None] (label bold)"
echo "  Time Spent: [time in minutes] (label bold)"
echo ""