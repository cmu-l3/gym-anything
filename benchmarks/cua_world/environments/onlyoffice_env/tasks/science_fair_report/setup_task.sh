#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Science Fair Report Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the raw notes file
NOTES_PATH="$WORKSPACE_DIR/raw_notes.txt"

cat > "$NOTES_PATH" << 'EOF'
EXPERIMENT NOTES - MESSY VERSION

My experiment was about testing if different colored lights make plants grow differently. I used red light bulbs, blue light bulbs, and normal white light as the control group. I thought that blue light would make plants grow the most because I read somewhere that blue light is good for photosynthesis and helps plants make energy. Plants need light to do photosynthesis which is how they make food for themselves using carbon dioxide and water and light energy.

HYPOTHESIS: If plants are grown under blue light, then they will grow taller than plants under red or white light because blue wavelengths are more efficiently absorbed by chlorophyll.

MATERIALS: 
9 bean plant seedlings (same age)
3 red LED light bulbs 60W
3 blue LED light bulbs 60W  
3 white LED light bulbs 60W (regular)
3 cardboard box chambers
Ruler for measuring
Potting soil
9 identical plastic cups
Water

I measured the plants every week. The data is in the other file.

OBSERVATIONS: The blue light plants looked healthier and grew fastest. Red light plants were kind of stretched out and skinny. White light plants were in the middle.

SOURCES I USED:
1. Smith, John. "How Light Affects Plant Growth." Science Learning Hub. https://www.sciencelearn.org.nz/light-and-plants
2. Garcia, Maria. "Photosynthesis and Light Wavelengths." Biology Basics Online. https://www.biologybasics.com/photosynthesis-wavelengths

CONCLUSION: My hypothesis was correct! Blue light made plants grow the tallest on average. This is because chlorophyll absorbs blue light wavelengths really well. Red light made plants grow but they were stretchy. White light was in between because it has all colors mixed together.
EOF

chown ga:ga "$NOTES_PATH"

# Create the plant data CSV file
DATA_PATH="$WORKSPACE_DIR/plant_data.csv"

cat > "$DATA_PATH" << 'EOF'
Plant_ID,Light_Color,Day_0_Height_cm,Day_7_Height_cm,Day_14_Height_cm
1,Red,2.0,4.5,8.2
2,Red,2.1,4.8,8.5
3,Red,1.9,4.3,7.9
4,Blue,2.0,6.2,12.4
5,Blue,2.1,6.5,12.8
6,Blue,1.9,6.0,12.0
7,White,2.0,5.1,10.1
8,White,2.1,5.3,10.5
9,White,1.9,4.9,9.8
EOF

chown ga:ga "$DATA_PATH"

echo "✅ Raw notes created at: $NOTES_PATH"
echo "✅ Plant data created at: $DATA_PATH"

# Create a starter document with just the file name (minimal template)
DOC_PATH="$WORKSPACE_DIR/science_fair_report.docx"

cat > /tmp/create_starter_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
import sys

doc = Document()

# Add a single paragraph as placeholder
doc.add_paragraph("Science Fair Report - Start Here")
doc.add_paragraph("")
doc.add_paragraph("Instructions:")
doc.add_paragraph("1. Refer to raw_notes.txt and plant_data.csv in this folder")
doc.add_paragraph("2. Create a formatted report with:")
doc.add_paragraph("   - Title page (centered)")
doc.add_paragraph("   - Abstract (max 150 words)")
doc.add_paragraph("   - Hypothesis, Materials, Results, Conclusion, References sections")
doc.add_paragraph("   - Data table with calculated averages")
doc.add_paragraph("   - At least 2 citations")

doc.save(sys.argv[1])
print(f"Starter document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_starter_doc.py
python3 /tmp/create_starter_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Starter document created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_sciencefair_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_sciencefair_task.log || true
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

echo "=== Science Fair Report Task Setup Complete ==="
echo "📝 Context: It's 9:30 PM the night before the district science fair"
echo "📝 Task: Compile scattered notes into a properly formatted report"
echo ""
echo "Data files available:"
echo "  - $NOTES_PATH (experiment description, hypothesis, sources)"
echo "  - $DATA_PATH (raw plant measurements)"
echo ""
echo "Required report structure:"
echo "  1. Title page (centered): title, student name 'Jamie Chen', grade '7th Grade', school 'Lincoln Middle School', date"
echo "  2. Abstract (≤150 words)"
echo "  3. Hypothesis section (bold heading)"
echo "  4. Materials section (bold heading, bullet list)"
echo "  5. Results section with data table (calculated averages per light color)"
echo "  6. Conclusion section (bold heading)"
echo "  7. References section (at least 2 citations in format: Author. 'Title.' Website. URL)"
echo ""
echo "Save with Ctrl+S when complete"