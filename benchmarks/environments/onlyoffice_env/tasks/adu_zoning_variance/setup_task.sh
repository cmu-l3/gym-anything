#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up ADU Zoning Variance Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Define file paths
NOTES_FILE="$WORKSPACE_DIR/variance_notes.txt"
OUTPUT_FILE="$WORKSPACE_DIR/zoning_variance_application.docx"

# Create the messy notes file that the user needs to organize
cat > "$NOTES_FILE" << 'EOF'
VARIANCE APPLICATION NOTES - LISA HENDERSON
===========================================

PROPERTY INFO:
Address: 457 Maple Street, Riverside, State 12345
My phone: 555-0142
Parcel: 45-2891-023
Lot size: 50 feet wide, 120 feet deep

PROBLEM:
Want to convert garage to ADU for Mom (78 yrs old). Garage is 4 ft from back fence.
City code says needs to be 6 feet. Need variance for 2 feet.

REASONS WHY I NEED THIS:
- Mom can't live alone anymore but hates nursing homes
- Assisted living costs $4000/MONTH!! (can't afford that)
- Garage been there since 1985, nobody ever complained
- If I have to demolish & rebuild further forward, costs $80,000 more
- Family wants to stay together

NEIGHBOR SUPPORT (collected signatures):
✓ 455 Maple - Johnsons said YES (gave written letter)
✓ 459 Maple - Patels YES (wrote letter)
✓ 456 Maple - Chens said ok (letter received)  
✓ 458 Maple - Martinez family supports it (verbal - need to get written)
? 454 Maple - Thompsons didn't answer door (tried 3 times)
? 460 Maple - Wilsons are on vacation, haven't talked to them

WHY IT'S OK:
- Structure already exists! Not building NEW thing in setback
- There's hedges on that side (mature privet hedge, like 8 ft tall)
- Nobody can even see the garage from their yard
- City WANTS more ADUs (they passed new ordinance last year)
- Setbacks are about light/air/privacy - this doesn't affect any of that

HEARING: March 15, 2024 (get exact date from clerk)

WHAT TO INCLUDE???:
- Found examples online but they all look different
- One person said include financial info, another said don't
- How formal does it need to be???
- Should I attach photos? contractor plans?

MEASUREMENTS FROM CONTRACTOR:
- Garage footprint: 20 ft x 24 ft (480 sq ft)
- Distance from rear property line: 4 feet 3 inches (measured with tape)
- Code requirement: Section 18.24.050 says 6 feet minimum
- Difference: Need 2 foot variance (well, 1 ft 9 in technically)

TALKING POINTS FOR JUSTIFICATION:
* Pre-existing nonconforming structure (built 1985)
* Unusual lot configuration (narrow lot, house positioned forward)
* Literal interpretation creates practical difficulty
* Variance maintains neighborhood character
* Promotes family unity and aging-in-place (city policy goal)
* No neighbor opposition

MORE INFO:
- Garage is detached, single story
- Will be renovated to be 450 sq ft living space
- Includes kitchenette, bathroom, bedroom area
- Utilities already run to garage (electric, water)
- No impact on drainage or parking
- Property is in R-1 Single Family zone

CONTACT INFO:
Lisa Henderson
457 Maple Street
Riverside, State 12345
Phone: (555) 867-0142
Email: lhenderson@email.com

APPLICATION DEADLINE: Must submit 2 weeks before hearing!
EOF

chown ga:ga "$NOTES_FILE"

echo "✅ Notes file created at: $NOTES_FILE"

# Create a blank starter document for the user
cat > /tmp/create_starter_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Inches
import sys

doc = Document()

# Set margins
sections = doc.sections
for section in sections:
    section.top_margin = Inches(1)
    section.bottom_margin = Inches(1)
    section.left_margin = Inches(1)
    section.right_margin = Inches(1)

# Add a placeholder paragraph to make it non-empty
doc.add_paragraph("[Create your zoning variance application here]")
doc.add_paragraph("")
doc.add_paragraph("Hint: Open the file 'variance_notes.txt' in your Documents/TextDocuments folder for the information you need.")

doc.save(sys.argv[1])
print(f"Starter document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_starter_doc.py
python3 /tmp/create_starter_doc.py "$OUTPUT_FILE"
chown ga:ga "$OUTPUT_FILE"

echo "✅ Starter document created at: $OUTPUT_FILE"

# Launch ONLYOFFICE with the output document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$OUTPUT_FILE' > /tmp/onlyoffice_variance_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_variance_task.log || true
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

echo "=== ADU Zoning Variance Task Setup Complete ==="
echo ""
echo "📋 TASK INSTRUCTIONS:"
echo "==========================================="
echo ""
echo "SCENARIO: Lisa needs to prepare a formal zoning variance application"
echo "for a hearing to convert her garage into an ADU for her elderly mother."
echo ""
echo "YOUR TASK: Create a professional application document with:"
echo ""
echo "1. TITLE (bold, centered, 14pt):"
echo "   'APPLICATION FOR ZONING VARIANCE'"
echo ""
echo "2. HEADER SECTION:"
echo "   - Property Address: 457 Maple Street, Riverside, State 12345"
echo "   - Parcel Number: 45-2891-023"
echo "   - Applicant: Lisa Henderson"
echo "   - Variance Type: Rear Setback Reduction"
echo "   - Hearing Date: March 15, 2024"
echo ""
echo "3. PROPERTY DETAILS TABLE (with borders):"
echo "   Include: lot dimensions, existing setback (4 feet),"
echo "   required setback (6 feet), variance requested (2 feet),"
echo "   structure purpose (ADU for elderly family member)"
echo ""
echo "4. JUSTIFICATION SECTION (3 numbered paragraphs):"
echo "   1. Hardship and Necessity"
echo "   2. Minimal Impact on Adjacent Properties"
echo "   3. Consistency with Zoning Intent"
echo ""
echo "5. NEIGHBOR SUPPORT TABLE (with borders):"
echo "   List 6 neighbors (455, 459, 456, 458, 454, 460 Maple St)"
echo "   Show support status for each"
echo ""
echo "📁 Source information: $NOTES_FILE"
echo "💾 Create document at: $OUTPUT_FILE"
echo ""
echo "Press Ctrl+S to save when complete!"
echo "==========================================="