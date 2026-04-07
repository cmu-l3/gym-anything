#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fire Investigation Report Task ==="

kill_calligra_processes

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

rm -f /home/ga/Documents/fire_investigation_report.odt
rm -f /home/ga/Desktop/nfpa921_formatting_spec.txt

# Create formatting spec
cat > /home/ga/Desktop/nfpa921_formatting_spec.txt << 'EOF'
NFPA 921 Report Formatting Specification

1. General Document Settings:
   - Body text should be justified alignment
   - Include a Table of Contents after the Cover Page elements

2. Title Page:
   - Report Title must be Bold and at least 14pt font size

3. Section Headings:
   - Format the 9 main report sections as Heading 1
   - Format the subsections (under Scene Documentation, Origin Analysis, Cause Analysis) as Heading 2

4. Emphasized Terminology:
   - The following key determinations must be formatted as Bold text where they appear in the narrative paragraphs:
     * Area of Origin
     * Point of Origin
     * Cause Classification: Accidental
     * First Fuel Ignited
     * Ignition Source

5. Tabular Data:
   - Convert the Evidence Collection items into a formatted table
   - Convert the Photo Log entries into a formatted table

6. Lists:
   - The Timeline of Events should be formatted as a list (numbered or bulleted)
EOF
chown ga:ga /home/ga/Desktop/nfpa921_formatting_spec.txt

# Create unformatted document
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# Cover Page elements
add_paragraph("Fire Investigation Report")
add_paragraph("Incident #2025-03847")
add_paragraph("Investigating Agency: Riverside Fire Department")
add_paragraph("Investigator: Captain John Doe, CFI")
add_paragraph("Date: March 15, 2025")
add_paragraph("")

add_paragraph("Executive Summary")
add_paragraph("This report documents the fire investigation for Incident #2025-03847 at 1847 Oakwood Drive. The investigation was conducted in accordance with NFPA 921 guidelines. The fire originated in Bedroom 2 and was caused by an unattended portable space heater igniting nearby polyester bedding. The Cause Classification: Accidental.")
add_paragraph("")

add_paragraph("Incident Background")
add_paragraph("On March 15, 2025, a residential structure fire was reported at 1847 Oakwood Drive. Engine 4 responded under the command of Chief Martinez. Weather conditions were clear, 65°F, with winds from the NW at 5 mph.")
add_paragraph("Timeline of Events")
add_paragraph("08:14: Initial 911 call received")
add_paragraph("08:15: Engine 4 dispatched")
add_paragraph("08:22: Engine 4 arrived on scene")
add_paragraph("08:45: Fire knocked down")
add_paragraph("09:10: Fire investigator requested")
add_paragraph("09:45: Investigator arrived on scene")
add_paragraph("10:05: Exterior scene documentation began")
add_paragraph("10:25: Interior scene documentation began")
add_paragraph("10:50: Point of origin identified")
add_paragraph("12:30: Scene released to owner")
add_paragraph("14:00: Investigation concluded")
add_paragraph("")

add_paragraph("Scene Documentation")
add_paragraph("Exterior Survey")
add_paragraph("The structure is a single-family, single-story dwelling of Type V wood-frame construction. The exterior showed minimal fire damage, limited to smoke staining above the Bedroom 2 window.")
add_paragraph("Interior Survey")
add_paragraph("Interior spaces showed heavy smoke damage throughout. Thermal damage was concentrated in the south quadrant of the structure, specifically in Bedroom 2.")
add_paragraph("Utilities Assessment")
add_paragraph("Electrical service is provided via an overhead drop to the Garage. The circuit breaker panel showed no tripped breakers prior to fire department operations.")
add_paragraph("")

add_paragraph("Origin Analysis")
add_paragraph("Fire Pattern Indicators")
add_paragraph("A pronounced V-pattern was observed on the south wall of Bedroom 2. Char depth analysis indicated the longest burn time near the floor level along this wall. Clean burn areas were identified on the floor.")
add_paragraph("Area of Origin Determination")
add_paragraph("Based on the fire pattern indicators and arc mapping of the bedroom circuits, the Area of Origin was determined to be the southeast corner of Bedroom 2. The Point of Origin was pinpointed to the floor area directly beneath the window where the space heater was located.")
add_paragraph("")

add_paragraph("Cause Analysis")
add_paragraph("Ignition Source Analysis")
add_paragraph("The remains of a portable electric space heater were found in the area of origin. Examination revealed severe melting of the plastic housing and arcing on the power cord. The Ignition Source was determined to be the radiating heating element of the space heater.")
add_paragraph("Cause Classification")
add_paragraph("The First Fuel Ignited was identified as the polyester bedding material that had fallen or been placed too close to the heater. Therefore, the Cause Classification: Accidental.")
add_paragraph("")

add_paragraph("Fire Spread Analysis")
add_paragraph("The fire spread from the bedding to the adjacent mattress and curtains, extending up the wall and involving the ceiling. Class II-B interior finish contributed to rapid flame spread.")
add_paragraph("")

add_paragraph("Evidence Collection")
add_paragraph("Item 1 - Melted space heater remains - Bedroom 2 - Collected")
add_paragraph("Item 2 - Burnt polyester bedding - Bedroom 2 - Collected")
add_paragraph("Item 3 - Arc mapped wire segment - Bedroom 2 wall - Collected")
add_paragraph("Item 4 - Smoke detector (melted) - Hallway - Collected")
add_paragraph("Item 5 - Outlet receptacle - Bedroom 2 - Collected")
add_paragraph("Item 6 - Carpet sample - Bedroom 2 floor - Collected")
add_paragraph("Item 7 - Circuit breaker panel - Garage - Photographed")
add_paragraph("Item 8 - Thermostat - Living room - Photographed")
add_paragraph("")

add_paragraph("Witness Statements")
add_paragraph("Witness 1: Mary Smith (Homeowner) - Stated she turned on the space heater and left the room briefly.")
add_paragraph("Witness 2: Bob Jones (Neighbor) - Reported seeing smoke coming from the bedroom window and called 911.")
add_paragraph("Witness 3: Capt. Davis (First-arriving) - Confirmed heavy smoke from the front door upon arrival.")
add_paragraph("Witness 4: Utility Tech - Verified power was secured at the pole.")
add_paragraph("")

add_paragraph("Photo Log")
add_paragraph("Photo 1 - Exterior view, front elevation - Front yard - 10:05")
add_paragraph("Photo 2 - Exterior view, Charlie side - Backyard - 10:12")
add_paragraph("Photo 3 - Interior view, living room - Living room - 10:25")
add_paragraph("Photo 4 - V-pattern on wall - Bedroom 2 - 10:45")
add_paragraph("Photo 5 - Point of origin - Bedroom 2 - 10:50")
add_paragraph("Photo 6 - Melted space heater - Bedroom 2 - 10:55")
add_paragraph("Photo 7 - Burnt bedding - Bedroom 2 - 11:00")
add_paragraph("Photo 8 - Arc mapped wire - Bedroom 2 wall - 11:10")
add_paragraph("Photo 9 - Outlet receptacle - Bedroom 2 - 11:15")
add_paragraph("Photo 10 - Smoke detector - Hallway - 11:25")
add_paragraph("Photo 11 - Circuit breaker panel - Garage - 11:35")
add_paragraph("Photo 12 - Thermostat - Living room - 11:45")

doc.save("/home/ga/Documents/fire_investigation_report.odt")
PYEOF
chown ga:ga /home/ga/Documents/fire_investigation_report.odt

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Launch Calligra Words with document
su - ga -c "DISPLAY=:1 /usr/bin/calligrawords /home/ga/Documents/fire_investigation_report.odt &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "calligrawords"; then
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r "calligrawords" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "calligrawords" 2>/dev/null || true
sleep 2

DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="