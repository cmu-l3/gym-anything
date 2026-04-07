#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Timber Harvest Plan Formatting Task ==="

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

kill_calligra_processes

rm -f /home/ga/Documents/bear_creek_thp.odt
rm -f /home/ga/Desktop/forestry_formatting_rules.txt

# Create the formatting specification on the Desktop
cat > /home/ga/Desktop/forestry_formatting_rules.txt << 'EOF'
STATE FORESTRY DEPARTMENT
TIMBER HARVEST PLAN FORMATTING RULES

1. Page Layout:
   - All document margins (Top, Bottom, Left, Right) must be set to exactly 1 inch (2.54 cm).
   - The document must contain a page header.

2. Header:
   - The header must contain exactly this text: "THP Name: Bear Creek Harvest"
   - The header text must be Right-Aligned.

3. Headings:
   - All 6 main section titles must be formatted as Heading 1 (General Information, Silviculture, Harvesting Practices, Erosion Control, Biological Resources, Alternatives).
   - All 8 subsection titles must be formatted as Heading 2.

4. Biological Nomenclature:
   - All Latin scientific names of species (appearing in parentheses after common names in the Biological Resources section) must be italicized. Do not italicize the parentheses or the common names.

5. Tables:
   - The Watercourse Protection data provided as plain text must be converted into a 4-column table (Watercourse Class, Characteristics, Protection Width, Canopy Retention).

6. Table of Contents:
   - A Table of Contents must be generated and placed at the beginning of the document.
EOF

chown ga:ga /home/ga/Desktop/forestry_formatting_rules.txt

# ---------------------------------------------------------------------------
# Create the unformatted THP document (all plain paragraphs, no styles)
# ---------------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

add_paragraph("Timber Harvest Plan")
add_paragraph("Bear Creek Harvest")
add_paragraph("")

# Section 1
add_paragraph("General Information")
add_paragraph("Site Description")
add_paragraph("The Bear Creek harvest area encompasses 150 acres of mixed conifer forest located in the coastal mountains. The topography consists of moderately to steeply sloping terrain, with elevations ranging from 400 to 1,200 feet above sea level. Soils in the harvest area are predominantly well-drained loams.")
add_paragraph("Stand Characteristics")
add_paragraph("The current stand is characterized by a dense, second-growth forest dominated by conifers, with a minor component of mixed hardwoods in the understory. The average basal area is approximately 250 square feet per acre, with trees ranging in age from 45 to 60 years.")
add_paragraph("")

# Section 2
add_paragraph("Silviculture")
add_paragraph("Silvicultural Methods")
add_paragraph("The primary silvicultural method prescribed for this THP is Selection. This uneven-aged management approach will promote a multi-aged stand structure and encourage the natural regeneration of shade-tolerant species. Approximately 30% of the standing inventory will be harvested.")
add_paragraph("")

# Section 3
add_paragraph("Harvesting Practices")
add_paragraph("Yarding Methods")
add_paragraph("Given the steep topography on portions of the site, a combination of tractor yarding and cable yarding will be utilized. Tractor yarding is restricted to slopes less than 40%. Cable yarding will be required for steeper terrain to minimize soil compaction and disturbance.")
add_paragraph("Winter Operations")
add_paragraph("No winter operations are proposed. All timber falling and yarding activities will occur during the dry season, defined as May 1 through October 15, to prevent excessive soil erosion and sediment transport.")
add_paragraph("")

# Section 4
add_paragraph("Erosion Control")
add_paragraph("Erosion control measures, including waterbars and rolling dips, will be installed on all skid trails and temporary roads prior to the winter period. Bare soil areas exceeding 100 square feet near watercourses will be mulched with certified weed-free straw.")
add_paragraph("")

# Section 5
add_paragraph("Biological Resources")
add_paragraph("Protected Species")
add_paragraph("The harvest area and adjacent biological assessment area have been surveyed for protected species. Habitat evaluations were conducted for the following key species: Coho Salmon (Oncorhynchus kisutch), Northern Spotted Owl (Strix occidentalis caurina), Pacific Fisher (Pekania pennanti), Foothill Yellow-legged Frog (Rana boylii), and Coast Redwood (Sequoia sempervirens). No active nests or dens were located within the proposed harvest units.")
add_paragraph("Watercourse Protection")
add_paragraph("The following watercourse and lake protection zone (WLPZ) standards will be applied:")
add_paragraph("Watercourse Class | Characteristics | Protection Width | Canopy Retention")
add_paragraph("Class I | Fish-bearing | 150 ft | 80% overstory canopy")
add_paragraph("Class II | Non-fish aquatic habitat | 100 ft | 50% overstory canopy")
add_paragraph("Class III | No aquatic life, capable of transport | 50 ft | 0% overstory canopy")
add_paragraph("")

# Section 6
add_paragraph("Alternatives")
add_paragraph("No Project Alternative")
add_paragraph("Under the No Project Alternative, no timber harvesting would occur. The stand would continue to grow densely, increasing competition for resources and potentially elevating the risk of catastrophic wildfire. This alternative does not meet the landowner's objectives for sustainable timber production.")

doc.save("/home/ga/Documents/bear_creek_thp.odt")
PYEOF

chown ga:ga /home/ga/Documents/bear_creek_thp.odt

# Launch Calligra Words with the document
echo "Launching Calligra Words..."
launch_calligra_document "/home/ga/Documents/bear_creek_thp.odt"

# Wait for Calligra window
wait_for_window "Calligra Words" 30

WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize window
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Record task start time (anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task Setup Complete ==="