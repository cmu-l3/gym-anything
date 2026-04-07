#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Property Inspection Report Task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

kill_calligra_processes
rm -f /home/ga/Documents/inspection_report.odt
rm -f /home/ga/Desktop/ashi_report_format.txt

# ------------------------------------------------------------------
# Create the formatting specification file
# ------------------------------------------------------------------
cat << 'EOF' > /home/ga/Desktop/ashi_report_format.txt
ASHI PROPERTY INSPECTION REPORT - FORMATTING SPECIFICATION

You must format the raw inspection notes to comply with the following standards:

1. TITLE:
   The main title ("Residential Property Inspection Report") must be Bold and at least 14pt font size.

2. PROPERTY INFORMATION BLOCK:
   The labels (e.g., "Report Number:", "Property Address:", "Client Name:", "Inspection Date:", "Inspector:", "Weather Conditions:") must be Bold. The values following them should be regular text.

3. SECTION HEADINGS:
   Apply "Heading 1" style to the 10 main report sections (Executive Summary, Structural Components, Exterior, Roofing, Plumbing, Electrical, Heating / HVAC, Interior, Insulation and Ventilation, Fireplace and Chimney).

4. SUBSECTION HEADINGS:
   Within the inspection areas, apply "Heading 2" style to the "Observations" and "Recommendations" headings.

5. SUMMARY CONDITION TABLE:
   In the Executive Summary section, convert the plain text list of overall area conditions into a proper Table (2 columns, at least 8 rows).

6. PER-SECTION RATING TABLES:
   In each of the other inspection sections (Structural, Exterior, Roofing, etc.), convert the plain text component ratings (e.g., "Foundation: Satisfactory", "Floor Structure: Marginal") into a proper Table. You should create at least 5 of these section-level tables throughout the document.

7. BODY TEXT:
   All standard body paragraphs (observations, descriptions) must be Justified alignment and at least 11pt font size.

Note: Do not delete any of the actual inspection findings or change the text content. Just apply the structure and formatting.
EOF
chown ga:ga /home/ga/Desktop/ashi_report_format.txt

# ------------------------------------------------------------------
# Create the unformatted Property Inspection Report using odfpy
# ALL content is plain P elements — no heading styles, no bold, no tables
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# Title & Info
add_paragraph("Residential Property Inspection Report")
add_paragraph("")
add_paragraph("Report Number: INS-2025-04172")
add_paragraph("Property Address: 2847 Sycamore Ridge Drive, Fort Collins, CO 80525")
add_paragraph("Client Name: Margaret and David Thornton")
add_paragraph("Inspection Date: April 17, 2025")
add_paragraph("Inspector: James R. Whitfield, ASHI Certified Inspector #258741")
add_paragraph("Weather Conditions: Clear, 58°F")
add_paragraph("")

# Section 1
add_paragraph("Executive Summary")
add_paragraph("The inspection was performed in accordance with ASHI Standards of Practice. The subject property is a single-family detached residential structure, estimated to be built in 1987. Overall, the property is in average condition for its age. Several maintenance items and a few safety concerns were identified that require attention.")
add_paragraph("")
add_paragraph("Overall Condition Summary:")
add_paragraph("Structural Components | Satisfactory")
add_paragraph("Exterior | Marginal")
add_paragraph("Roofing | Marginal")
add_paragraph("Plumbing | Satisfactory")
add_paragraph("Electrical | Defective / Safety Concern")
add_paragraph("Heating / HVAC | Satisfactory")
add_paragraph("Interior | Satisfactory")
add_paragraph("Insulation and Ventilation | Marginal")
add_paragraph("")

# Section 2
add_paragraph("Structural Components")
add_paragraph("Foundation | Satisfactory")
add_paragraph("Wall Framing | Satisfactory")
add_paragraph("Floor Structure | Satisfactory")
add_paragraph("Roof Framing | Satisfactory")
add_paragraph("Observations")
add_paragraph("The foundation is poured concrete. The visible portions of the foundation walls showed typical minor shrinkage cracks, but no significant structural movement was observed. Floor structure consists of dimensional lumber joists and plywood subflooring. Minor efflorescence was noted on the interior foundation wall in the northeast corner of the basement, indicating past moisture seepage.")
add_paragraph("Recommendations")
add_paragraph("Monitor: Ensure exterior grading directs water away from the northeast corner to prevent future moisture intrusion and efflorescence.")
add_paragraph("")

# Section 3
add_paragraph("Exterior")
add_paragraph("Siding and Trim | Marginal")
add_paragraph("Windows and Doors | Satisfactory")
add_paragraph("Decks and Balconies | Satisfactory")
add_paragraph("Grading and Drainage | Marginal")
add_paragraph("Observations")
add_paragraph("The exterior cladding is predominantly painted wood lap siding. Peeling paint and wood rot were observed on the lower courses of siding on the south elevation. Soil grading is neutral or slightly negative along the west foundation wall. The rear deck is pressure-treated lumber and appears structurally sound.")
add_paragraph("Recommendations")
add_paragraph("Repair Needed: Replace rotted wood siding on the south elevation and prep/paint to prevent further deterioration.")
add_paragraph("Repair Needed: Regrade soil along the west wall to ensure a positive slope of 6 inches over the first 10 feet away from the foundation.")
add_paragraph("")

# Section 4
add_paragraph("Roofing")
add_paragraph("Roof Covering | Marginal")
add_paragraph("Flashings | Satisfactory")
add_paragraph("Gutters and Downspouts | Marginal")
add_paragraph("Observations")
add_paragraph("The roof was inspected from the eaves via ladder and via binoculars from the ground. The asphalt shingle roof covering appears to be in the second half of its design life. Some granular loss and minor curling at the shingle edges were noted. Gutters are aluminum seamless, but the downspout at the front left discharges directly against the foundation.")
add_paragraph("Recommendations")
add_paragraph("Monitor: The asphalt shingles are aging. Budget for roof replacement within the next 3 to 5 years.")
add_paragraph("Repair Needed: Add a downspout extension to the front left gutter to discharge water at least 5 feet from the foundation.")
add_paragraph("")

# Section 5
add_paragraph("Plumbing")
add_paragraph("Water Supply Lines | Satisfactory")
add_paragraph("Drain/Waste/Vent Lines | Satisfactory")
add_paragraph("Water Heater | Marginal")
add_paragraph("Fixtures | Satisfactory")
add_paragraph("Observations")
add_paragraph("Visible water supply lines are copper. Drain lines are primarily PVC. The water heater is a 40-gallon natural gas unit manufactured in 2014. Galvanic corrosion was observed at the water heater connection where copper meets galvanized steel without a proper dielectric union.")
add_paragraph("Recommendations")
add_paragraph("Repair Needed: Have a qualified plumber install dielectric unions at the water heater to stop the galvanic corrosion before leakage occurs.")
add_paragraph("")

# Section 6
add_paragraph("Electrical")
add_paragraph("Service Entrance | Satisfactory")
add_paragraph("Main Panel | Satisfactory")
add_paragraph("Branch Circuits | Satisfactory")
add_paragraph("GFCI/AFCI Protection | Defective")
add_paragraph("Observations")
add_paragraph("The main service is 200-amp underground. The main panel is located in the garage. Wiring is copper NM cable (Romex). GFCI protection is missing at the kitchen island receptacle and at the exterior rear patio receptacle.")
add_paragraph("Recommendations")
add_paragraph("Safety Concern: Have a licensed electrician install GFCI protection for all kitchen countertop and exterior receptacles to reduce shock hazard.")
add_paragraph("")

# Section 7
add_paragraph("Heating / HVAC")
add_paragraph("Heating Equipment | Satisfactory")
add_paragraph("Cooling Equipment | Satisfactory")
add_paragraph("Ductwork | Satisfactory")
add_paragraph("Observations")
add_paragraph("The heating system is a Lennox forced-air natural gas furnace, manufactured in 2020. The air conditioning condenser is a matching Lennox unit. Both units responded normally to the thermostat during the inspection. The air filter is clean.")
add_paragraph("Recommendations")
add_paragraph("Informational: Continue with annual professional servicing of the HVAC system to ensure optimal efficiency and longevity.")
add_paragraph("")

# Section 8
add_paragraph("Interior")
add_paragraph("Walls and Ceilings | Satisfactory")
add_paragraph("Floors | Satisfactory")
add_paragraph("Doors and Windows | Satisfactory")
add_paragraph("Observations")
add_paragraph("Interior finishes are generally in good condition with typical cosmetic wear. Double-pane vinyl windows operate smoothly. No evidence of active roof leaks was observed on the second-floor ceilings.")
add_paragraph("Recommendations")
add_paragraph("Informational: Minor drywall nail pops and settling cracks noted; these are cosmetic and do not indicate structural defects.")
add_paragraph("")

# Section 9
add_paragraph("Insulation and Ventilation")
add_paragraph("Attic Insulation | Marginal")
add_paragraph("Attic Ventilation | Satisfactory")
add_paragraph("Observations")
add_paragraph("Attic insulation is blown-in fiberglass, averaging about 8-10 inches in depth (approximate R-value of R-25). Current energy standards recommend R-38 to R-60 for this climate zone. Soffit and ridge vents provide adequate attic ventilation.")
add_paragraph("Recommendations")
add_paragraph("Repair Needed: Consider adding insulation to the attic to reach R-38 or higher to improve energy efficiency and comfort.")
add_paragraph("")

# Section 10
add_paragraph("Fireplace and Chimney")
add_paragraph("Firebox and Damper | Satisfactory")
add_paragraph("Flue | Not Inspected")
add_paragraph("Exterior Chimney | Marginal")
add_paragraph("Observations")
add_paragraph("The living room features a masonry wood-burning fireplace. The damper operates correctly. The exterior brick chimney shows some deteriorated mortar joints (tuckpointing needed) near the top, and the metal chimney cap is heavily rusted.")
add_paragraph("Recommendations")
add_paragraph("Repair Needed: Have a masonry contractor tuckpoint the deteriorated mortar joints on the chimney and replace the rusted chimney cap to prevent water intrusion.")

doc.save("/home/ga/Documents/inspection_report.odt")
PYEOF

chown ga:ga /home/ga/Documents/inspection_report.odt

# Launch Calligra Words with the document
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid calligrawords /home/ga/Documents/inspection_report.odt > /tmp/calligra.log 2>&1 < /dev/null &"

# Wait for window and maximize
sleep 5
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png ga

echo "=== Task Setup Complete ==="