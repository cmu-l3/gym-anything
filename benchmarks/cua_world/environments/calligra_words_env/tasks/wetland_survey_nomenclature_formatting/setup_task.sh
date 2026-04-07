#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Wetland Survey Nomenclature Formatting Task ==="

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop
kill_calligra_processes
rm -f /home/ga/Documents/blackwood_wetland_survey.odt
rm -f /home/ga/Desktop/dep_report_guidelines.txt

date +%s > /tmp/task_start_time.txt

cat > /home/ga/Desktop/dep_report_guidelines.txt << 'EOF'
STATE DEPARTMENT OF ENVIRONMENTAL PROTECTION (DEP)
WETLAND SURVEY REPORT FORMATTING GUIDELINES

1. SECTION HEADINGS
- The following must be formatted as Heading 1 (Main Sections):
  * Introduction
  * Methodology
  * Site Description
  * Flora and Fauna Inventory
  * Conservation Recommendations
  
- The following must be formatted as Heading 2 (Subsections):
  * Hydrology
  * Soil Composition
  * Canopy Layer
  * Understory

2. TABLE OF CONTENTS
- A Table of Contents must be inserted immediately following the Introduction section.

3. SCIENTIFIC NOMENCLATURE
- Standard biological publishing conventions require that all Latin binomials (scientific names) be italicized.
- You must find and italicize EVERY instance of the following scientific names in the document:
  * Acer rubrum (Red Maple)
  * Typha latifolia (Broadleaf Cattail)
  * Clemmys guttata (Spotted Turtle)
  * Lithobates catesbeianus (American Bullfrog)
  * Ardea herodias (Great Blue Heron)
  * Chrysemys picta (Painted Turtle)
- WARNING: Do NOT italicize the common names (e.g., do not italicize "red maple").

4. OBSERVATION DATA
- The raw comma-separated observation data at the end of the report (under Flora and Fauna Inventory) must be converted into a table.
- The table must have 4 columns and include a header row.
EOF
chown ga:ga /home/ga/Desktop/dep_report_guidelines.txt

python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

add_paragraph("Blackwood Wetland Reserve - Ecological Survey Report")
add_paragraph("Date: May 12, 2026")
add_paragraph("Surveyor: Dr. Aris Thorne, Lead Ecologist")
add_paragraph("")

add_paragraph("Introduction")
add_paragraph(
    "This report details the findings of a comprehensive ecological survey conducted at the Blackwood Wetland Reserve. "
    "The primary objective was to assess the health of the ecosystem, document species biodiversity, and identify any "
    "immediate threats to the habitat. The Blackwood Wetland Reserve serves as a critical buffer zone for the "
    "surrounding watershed, providing flood mitigation and supporting a rich variety of hydrophytic vegetation and "
    "wildlife."
)
add_paragraph("")

add_paragraph("Methodology")
add_paragraph(
    "The survey utilized transect sampling and point-count observations over a 48-hour period. "
    "Water quality was measured using multiparameter sondes, and soil core samples were extracted at 50-meter intervals "
    "along the primary transect. Amphibian and reptile populations were assessed using visual encounter surveys."
)
add_paragraph("")

add_paragraph("Site Description")
add_paragraph("Hydrology")
add_paragraph(
    "Water levels are currently stable, though slightly below the five-year average for this season. "
    "Surface water pH was recorded at 6.8, indicating a healthy, slightly acidic environment typical of such ecosystems."
)
add_paragraph("Soil Composition")
add_paragraph(
    "Soil analysis confirmed the presence of hydric soils, primarily consisting of high-organic-content peat overlaying "
    "a clay restrictive layer, which maintains the perched water table necessary for the wetland's survival."
)
add_paragraph("")

add_paragraph("Flora and Fauna Inventory")
add_paragraph("Canopy Layer")
add_paragraph(
    "The overstory is dominated by red maple (Acer rubrum), which provides significant shade to the understory. "
    "Several mature Acer rubrum specimens exhibited signs of early-stage fungal infection, which warrants future monitoring."
)
add_paragraph("Understory")
add_paragraph(
    "The herbaceous layer is dense, heavily populated by broadleaf cattail (Typha latifolia). The expansive Typha latifolia "
    "beds offer excellent cover for nesting waterfowl and breeding amphibians."
)
add_paragraph(
    "Wildlife observations were abundant. We noted several amphibian species, prominently the American bullfrog "
    "(Lithobates catesbeianus). The Lithobates catesbeianus population appears robust, with numerous egg masses observed "
    "in the shallower pools. Avian activity was highlighted by the presence of a great blue heron (Ardea herodias), "
    "seen foraging near the northern inlet. Ardea herodias rely on the abundant fish and amphibian prey in this area."
)
add_paragraph(
    "Reptile sightings included the painted turtle (Chrysemys picta) basking on submerged logs, and a rare sighting "
    "of the spotted turtle (Clemmys guttata). The presence of Clemmys guttata is particularly encouraging, as they "
    "are an indicator species of high water quality. Both Chrysemys picta and Clemmys guttata populations appear stable."
)
add_paragraph("")

add_paragraph("Raw Observation Data")
add_paragraph("Common Name, Scientific Name, Count, Location Status")
add_paragraph("Red Maple, Acer rubrum, 45, Abundant")
add_paragraph("Broadleaf Cattail, Typha latifolia, >500, Dominant")
add_paragraph("American Bullfrog, Lithobates catesbeianus, 32, Common")
add_paragraph("Painted Turtle, Chrysemys picta, 14, Common")
add_paragraph("Spotted Turtle, Clemmys guttata, 2, Rare")
add_paragraph("Great Blue Heron, Ardea herodias, 1, Transient")
add_paragraph("")

add_paragraph("Conservation Recommendations")
add_paragraph(
    "Based on the survey results, the Blackwood Wetland Reserve is in good ecological condition. However, to ensure "
    "the continued viability of sensitive species like Clemmys guttata, it is recommended that human foot traffic "
    "be restricted in the northern breeding pools. Ongoing monitoring of the Acer rubrum fungal infections should "
    "be established."
)

doc.save("/home/ga/Documents/blackwood_wetland_survey.odt")
PYEOF

chown ga:ga /home/ga/Documents/blackwood_wetland_survey.odt

# Launch Calligra Words
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid calligrawords /home/ga/Documents/blackwood_wetland_survey.odt >/tmp/calligra.log 2>&1 < /dev/null &"

# Wait for Calligra window
wait_for_window "Calligra" 20

# Maximize Calligra window
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    # Dismiss any startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task Setup Complete ==="