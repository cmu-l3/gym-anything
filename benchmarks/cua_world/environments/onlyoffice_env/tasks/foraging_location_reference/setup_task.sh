#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Foraging Location Reference Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial document with messy foraging notes
DOC_PATH="$WORKSPACE_DIR/foraging_notes.docx"

cat > /tmp/create_foraging_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
import sys

doc = Document()

# Add messy, unformatted content as described in the task
doc.add_paragraph("FORAGING LOCATIONS - FALL 2024")
doc.add_paragraph("")

doc.add_paragraph("Location 1 - Oak Ridge Trail")
doc.add_paragraph("GPS: 42.3601° N, 71.0589° W (parking lot)")
doc.add_paragraph("Mushrooms: Chicken of the Woods (summer-fall), Hen of the Woods (late fall), Oyster (spring+fall)")
doc.add_paragraph("Notes: Walk 0.4 miles from parking lot, look at base of large oak cluster on LEFT side of trail. Property line is unclear here - stay on obvious trail. DO NOT confuse Chicken of the Woods with Jack-O-Lantern (poisonous look-alike, check for gills).")
doc.add_paragraph("")

doc.add_paragraph("Location 2 - Riverside Conservation Area")
doc.add_paragraph("42°21'36.5\"N 71°03'28.7\"W")
doc.add_paragraph("Species: Morels (spring only, late April-May), Chanterelles (July-Sept), Black Trumpets (Aug-Oct)")
doc.add_paragraph("Near the old stone bridge foundation. Morels appear 2-3 weeks after last frost when soil temp hits 50F. Chanterelles grow under hemlock grove after heavy rain (needs 2+ inches within 7 days). BLACK BEARS active in this area August-October - make noise, carry spray.")
doc.add_paragraph("")

doc.add_paragraph("Location 3 - Meadowbrook Park South Entrance")
doc.add_paragraph("GPS coordinates: 42.3456, -71.0234")
doc.add_paragraph("Best in spring (April-May) for morels and dryad's saddle. Fall (Sept-Nov) for honey mushrooms and turkey tail (medicinal). Honey mushrooms can cause gastric upset in some people - always cook thoroughly, try small amount first. Park closes at sunset - no night foraging. Some mushrooms near parking lot may be contaminated from road salt runoff.")
doc.add_paragraph("")

doc.add_paragraph("IDENTIFICATION RULES:")
doc.add_paragraph("- Never eat anything without 100% positive ID")
doc.add_paragraph("- Check spore print color")
doc.add_paragraph("- Photograph gills/pores, stem, cap, and base before harvesting")
doc.add_paragraph("- When in doubt, throw it out")

doc.save(sys.argv[1])
print(f"Foraging document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_foraging_doc.py
python3 /tmp/create_foraging_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Foraging notes document created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_foraging_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_foraging_task.log || true
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

echo "=== Foraging Location Reference Task Setup Complete ==="
echo "📝 Instructions:"
echo "  Transform the messy foraging notes into a professional reference document:"
echo ""
echo "  1. Add a document title: 'Marcus's Fall Foraging Reference Guide - 2024'"
echo "     - Format as: Bold, Centered, 16pt font"
echo ""
echo "  2. Format each location with:"
echo "     - Bold location name as heading (14pt)"
echo "     - Standardized GPS coordinates (decimal format: 42.XXXX, -71.XXXX)"
echo "     - Seasonal information"
echo "     - Species list"
echo "     - Safety warnings in BOLD"
echo ""
echo "  3. Create a table showing seasonal availability:"
echo "     - Columns: Location | Spring (Apr-May) | Summer (Jun-Aug) | Fall (Sep-Nov)"
echo "     - Fill with species available in each season"
echo ""
echo "  4. Create a 'Safety Checklist' section at the end:"
echo "     - Include all safety warnings mentioned"
echo "     - Include identification rules"
echo "     - Format warnings in BOLD"
echo ""
echo "  5. Save the document (Ctrl+S)"
echo ""
echo "⚠️  Critical: Safety information must be prominent - lives depend on it!"