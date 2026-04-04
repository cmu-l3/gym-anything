#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Rescue Pet Care Planner Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the raw information file on desktop
RAW_FILE="/home/ga/Desktop/Bailey_Info_Raw.txt"

cat > "$RAW_FILE" << 'EOF'
BAILEY - RESCUE DOG CARE INFORMATION
(Compiled from various sources - needs organization!)

=== EMAIL FROM FOSTER MOM (Sarah) - Nov 18 ===
Hey Maya! So excited Bailey is going to his forever home! Quick notes:

Bailey is the SWEETEST boy but he needs patience. He was in a house with 40+ dogs so he's still learning what normal life is like. 

THINGS THAT SCARE HIM:
- Raised voices or yelling (even if not directed at him)
- Quick hand movements near his head (he flinches)
- Brooms and vacuums - he hides under the bed
- Men with beards (working on this in training)
- Sudden loud noises (doorbell, dropping pans)

WHAT HELPS:
- Soft voice, slow movements
- Let him come to you, don't corner him
- His favorite toy is the purple squeaky duck
- Frozen Kong with peanut butter when you leave the house
- He LOVES being brushed - very calming for him

FOOD: He's on Pro Plan Sensitive Stomach. Feed 2x daily. NO raw vegetables (he vomits), NO dairy. He can have cooked chicken or turkey as treats.

=== VET RECORDS FROM PINE STREET ANIMAL CLINIC ===
Patient: Bailey (Rescue ID: HH-2847)
Breed: Labrador/Shepherd Mix
Age: Approximately 4 years
Weight: 45 lbs
Microchip: 985112001234567

MEDICAL CONDITIONS:
1. Hip Dysplasia (moderate) - diagnosed via X-ray 3/15/24
2. Chronic anxiety - likely from previous environment
3. Healed fracture, right front leg (old injury, healed)

CURRENT MEDICATIONS:
1. Carprofen (Rimadyl) - 2.2 mg per pound body weight, divided into 2 doses daily
   Give WITH food to prevent stomach upset
   
2. Fluoxetine - 1mg per pound, once daily in morning
   Can be given with or without food
   NOTE: May take 4-6 weeks to see full effect

3. Glucosamine supplement - 500mg twice daily with meals

EXERCISE RESTRICTIONS:
- No running on hard surfaces (pavement)
- Avoid jumping (stairs okay, but discourage jumping on/off furniture)
- Swimming is EXCELLENT for hip dysplasia - highly recommended
- Short walks 3-4x daily better than one long walk

FOLLOW-UP REQUIRED:
- Recheck appointment in 2 weeks to assess anxiety medication effectiveness
- Hip X-rays in 6 months to monitor progression

DIET NOTE: Has done well with small amounts of carrots and green beans as low-calorie treats during weight loss program.

=== TEXT MESSAGES FROM RESCUE COORDINATOR (Jamie) - Nov 19 ===

Jamie: "BTW Bailey does great with other dogs but needs slow introductions. No dog parks yet - too overwhelming."

Jamie: "He's house-trained but might have accidents first week due to stress. Not his fault! Just be patient."

Jamie: "Crate training: He sees crate as safe space. Leave it open always. Feed him in there. Work up to closing door for short periods."

Jamie: "IMPORTANT - Emergency vet is Valley Animal Hospital, 555-0199. After hours poison control: 888-426-4435"

Jamie: "For the first week try to keep things VERY calm and routine. Same wake time, same walk times, same feeding times. Structure = security for anxious dogs."

Jamie: "Oh and he's not great with kids under 8 - too unpredictable for him. He doesn't bite but he gets stressed and hides."

=== PHONE CALL NOTES (Your handwriting) ===

Talked to Sarah on 11/20:
- Bailey sleeps in crate at night, door closed, no issues
- Morning routine: potty, breakfast, short walk, then he naps
- Evening: dinner, longer walk, playtime, Kong toy, bed by 10pm
- He tells you when he needs to go out - paces by door and whines a little
- First few days he might not eat much - normal stress response
- Week 1 goal: just let him decompress, don't push socialization
- Week 2: start inviting calm friends over one at a time
- Signs he's doing well: eating normally, playing with toys, "talking" (he makes funny grumbles when happy)

RED FLAGS - call vet immediately:
- Limping or refusing to put weight on back legs
- Vomiting more than once
- Diarrhea lasting more than 24 hours  
- Extreme lethargy (sleeping all day, won't get up)
- Aggression (growling, snapping) - he's never done this but watch for it

Sarah said: "The best thing you can do is just BE BORING for the first week. Boring is good for Bailey."

=== YOUR OWN NOTES ===
Adoption trial period: 30 days
If any issues, rescue takes him back - but I don't want that to happen!
Sarah's number: 555-0147 (can text with questions)
Roommate Alex will help with midday potty break on weekdays
Need to arrange pet sitter for Dec 5-7 work trip
Budget: $120/month for food, meds, treats
EOF

chown ga:ga "$RAW_FILE"

echo "✅ Raw information file created at: $RAW_FILE"

# Create a starter document with instructions
DOC_PATH="$WORKSPACE_DIR/Bailey_Care_Plan.docx"

cat > /tmp/create_starter_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt, RGBColor
import sys

doc = Document()

# Add title and instructions
title = doc.add_paragraph()
title_run = title.add_run("Bailey's Care Plan")
title_run.font.size = Pt(20)
title_run.bold = True

doc.add_paragraph("")

instructions = doc.add_paragraph()
instructions_run = instructions.add_run("INSTRUCTIONS: Read the file Bailey_Info_Raw.txt on the Desktop. Organize the scattered information below into a clear, structured care plan.")
instructions_run.font.size = Pt(11)
instructions_run.italic = True

doc.add_paragraph("")
doc.add_paragraph("=" * 60)
doc.add_paragraph("")

# Add section headers as a guide (optional - helps user structure)
doc.add_paragraph("Suggested sections to include:")
doc.add_paragraph("• Daily Medication Schedule (use a table)")
doc.add_paragraph("• Behavioral Triggers & Calming Techniques")
doc.add_paragraph("• Exercise & Activity Routine")
doc.add_paragraph("• Emergency Contact Information")
doc.add_paragraph("• First Week Adjustment Plan")

doc.add_paragraph("")
doc.add_paragraph("=" * 60)
doc.add_paragraph("")
doc.add_paragraph("[Start your organized care plan below]")
doc.add_paragraph("")

doc.save(sys.argv[1])
print(f"Starter document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_starter_doc.py
python3 /tmp/create_starter_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Starter document created at: $DOC_PATH"

# Launch ONLYOFFICE with the starter document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_rescue_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_rescue_task.log || true
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

echo "=== Rescue Pet Care Planner Task Setup Complete ==="
echo "📝 Task Overview:"
echo "  1. Read Bailey_Info_Raw.txt on the Desktop"
echo "  2. Organize the information into the care plan document"
echo "  3. Create a medication schedule TABLE with calculated dosages"
echo "     - Carprofen: 2.2 mg/lb × 45 lbs = 99mg total (split into 2 doses)"
echo "     - Fluoxetine: 1 mg/lb × 45 lbs = 45mg once daily"
echo "     - Glucosamine: 500mg twice daily"
echo "  4. Document behavioral triggers and responses"
echo "  5. Include emergency contacts and important info"
echo "  6. Save the document (Ctrl+S)"
echo ""
echo "Expected sections:"
echo "  • Daily Medication Schedule (as a table)"
echo "  • Behavioral Triggers & Calming Techniques"
echo "  • Exercise Routine (considering hip dysplasia)"
echo "  • Emergency Contact Information"
echo "  • First Week Adjustment Goals"