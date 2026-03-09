#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Plant Care Handoff Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the starter document with guidance
DOC_PATH="$WORKSPACE_DIR/plant_care_instructions.docx"

cat > /tmp/create_plant_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
import sys

doc = Document()

# Add title (user needs to format this as Heading 1)
title = doc.add_paragraph("Emergency Plant Care Instructions")
title.alignment = WD_ALIGN_PARAGRAPH.CENTER

# Add placeholder for date range
date_para = doc.add_paragraph("[Add date range here, e.g., January 15 - February 5, 2024]")
date_para.alignment = WD_ALIGN_PARAGRAPH.CENTER
doc.add_paragraph("")

# Add instruction for summary table
doc.add_paragraph("Quick Reference Summary")
doc.add_paragraph("[Create a table below with columns: Plant Name | Location | Water Frequency | Special Notes]")
doc.add_paragraph("[Add 6 rows - one for each plant]")
doc.add_paragraph("")
doc.add_paragraph("")

# Add instruction for detailed sections
doc.add_paragraph("Detailed Care Instructions")
doc.add_paragraph("")
doc.add_paragraph("[For each of your 6 plants, create a section below with:]")
doc.add_paragraph("  • Plant name as Heading 2")
doc.add_paragraph("  • Location description (where to find it)")
doc.add_paragraph("  • Detailed watering instructions (HOW, WHEN, HOW MUCH)")
doc.add_paragraph("  • At least one special instruction (light, temperature, warnings, etc.)")
doc.add_paragraph("")

# Add example plant (user should replace/expand)
example = doc.add_paragraph("Example Plant (Snake Plant)")
doc.add_paragraph("Location: Tall plant in living room corner")
doc.add_paragraph("Watering: Water every 2-3 weeks, only when soil completely dry. Pour 1 cup around edges.")
doc.add_paragraph("Special: Very drought-tolerant. If unsure, skip watering - overwatering kills these plants.")
doc.add_paragraph("")
doc.add_paragraph("[Add 5 more plant sections following this pattern]")
doc.add_paragraph("")
doc.add_paragraph("")
doc.add_paragraph("")

# Add placeholder for emergency contact
doc.add_paragraph("Emergency Contacts")
doc.add_paragraph("[Add your contact information here]")
doc.add_paragraph("[Make 'EMERGENCY' text bold for visibility]")
doc.add_paragraph("[Include backup expert contact if available]")

doc.save(sys.argv[1])
print(f"Plant care document template created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_plant_doc.py
python3 /tmp/create_plant_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Document template created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_plant_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_plant_task.log || true
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

echo "=== Plant Care Handoff Task Setup Complete ==="
echo ""
echo "📝 SCENARIO: You're unexpectedly leaving for 2-3 weeks and need to create"
echo "   care instructions for a neighbor with NO plant experience."
echo ""
echo "✅ REQUIRED ELEMENTS:"
echo "   1. Title: 'Emergency Plant Care Instructions' (format as Heading 1)"
echo "   2. Date range (e.g., Jan 15 - Feb 5, 2024)"
echo "   3. Summary TABLE with 6 plants:"
echo "      Columns: Plant Name | Location | Water Frequency | Special Notes"
echo "   4. Six detailed sections (one per plant):"
echo "      - Plant name as Heading 2"
echo "      - Location description"
echo "      - Detailed watering instructions"
echo "      - Special care notes"
echo "   5. Emergency contact section with BOLD 'EMERGENCY' text"
echo ""
echo "💡 TIP: Include plants with different needs (some thirsty, some drought-tolerant)"
echo "   Make instructions beginner-friendly - your neighbor is scared of killing them!"
echo ""
echo "⌨️  Save the document when complete (Ctrl+S)"