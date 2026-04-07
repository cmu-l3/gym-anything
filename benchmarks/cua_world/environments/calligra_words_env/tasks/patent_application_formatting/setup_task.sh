#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Patent Application Formatting Task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

kill_calligra_processes

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

rm -f /home/ga/Documents/patent_application.odt
rm -f /home/ga/Desktop/uspto_formatting_requirements.txt

# ------------------------------------------------------------------
# Create the formatting specification text file
# ------------------------------------------------------------------
cat << 'EOF' > /home/ga/Desktop/uspto_formatting_requirements.txt
USPTO FORMATTING REQUIREMENTS (37 CFR 1.52)

To ensure acceptance by the Patent Center, the application must be formatted as follows:

1. TITLE: The title of the invention must be Bold and at least 14pt font.
2. SECTION HEADINGS: Main sections (Cross-Reference to Related Applications, Field of the Invention, Background of the Invention, Summary of the Invention, Brief Description of the Drawings, Detailed Description of Preferred Embodiments, Claims, Abstract) must be clearly distinguished using the Heading 1 style.
3. BODY TEXT FONT: All regular body text must be at least 12pt font size.
4. ALIGNMENT: Text must be left-aligned (flush left, ragged right). Do not use justified alignment.
5. LINE SPACING: Body text must have at least 1.5 line spacing (150%) to allow for examiner annotations.
6. CLAIMS SECTION:
   - Claims must be sequentially numbered starting with 1. (e.g., "1. ", "2. ", etc.)
   - Independent claims must start at the left margin.
   - Dependent claims (claims that refer back to another claim, e.g., "The system of claim 1...") must be indented.
7. ABSTRACT: The abstract section must exist with a Heading 1, but the abstract text itself must be a single regular body paragraph (the abstract text itself should not be formatted as a heading).
EOF

chown ga:ga /home/ga/Desktop/uspto_formatting_requirements.txt

# ------------------------------------------------------------------
# Create the unformatted Patent Application document using odfpy
# ALL content is plain P elements — no heading styles, no bold, etc.
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# ── Title ──
add_paragraph("ELECTROCHEMICAL WATER PURIFICATION SYSTEM USING GRAPHENE-OXIDE COMPOSITE ELECTRODES")
add_paragraph("")

# ── Sections ──
add_paragraph("Cross-Reference to Related Applications")
add_paragraph("This application claims the benefit of U.S. Provisional Application No. 63/123,456 filed on January 10, 2025, the entire contents of which are incorporated herein by reference.")
add_paragraph("")

add_paragraph("Field of the Invention")
add_paragraph("The present invention relates generally to water purification systems, and more particularly to electrochemical water treatment using graphene-oxide composite electrodes for the removal of heavy metals and organic contaminants.")
add_paragraph("")

add_paragraph("Background of the Invention")
add_paragraph("Activated carbon filters and reverse osmosis membranes have traditionally been employed for municipal and industrial water purification. However, these conventional systems suffer from rapid membrane fouling, high energy consumption, and limited efficacy against emerging micro-pollutants.")
add_paragraph("Electrochemical oxidation methods offer a promising alternative by generating reactive oxygen species in situ. Conventional electrodes, such as boron-doped diamond or dimensionally stable anodes, are prohibitively expensive for large-scale deployment and exhibit degradation over extended operational cycles.")
add_paragraph("Therefore, there remains a critical need in the art for a highly efficient, durable, and cost-effective electrochemical water purification system capable of sustained operation in diverse aqueous environments.")
add_paragraph("")

add_paragraph("Summary of the Invention")
add_paragraph("The present disclosure provides a system and method for electrochemical water purification utilizing advanced graphene-oxide composite electrodes. The system comprises a reaction chamber, an anode, a cathode, and a power supply, wherein at least one of the electrodes comprises a high-surface-area graphene-oxide matrix doped with transition metal nanoparticles.")
add_paragraph("Advantageously, the described system achieves superior contaminant degradation rates while preventing passivation and membrane fouling, thereby significantly extending the operational lifespan of the purification apparatus compared to prior art solutions.")
add_paragraph("")

add_paragraph("Brief Description of the Drawings")
add_paragraph("FIG. 1 is a schematic diagram of the electrochemical water purification system in accordance with a preferred embodiment.")
add_paragraph("FIG. 2 is a cross-sectional view of the graphene-oxide composite electrode assembly.")
add_paragraph("FIG. 3 is a graph illustrating the degradation rate of organic contaminants over time.")
add_paragraph("FIG. 4 is a flow chart depicting the method of water purification.")
add_paragraph("FIG. 5 is a block diagram of the continuous recirculation subsystem.")
add_paragraph("")

add_paragraph("Detailed Description of Preferred Embodiments")
add_paragraph("In a preferred embodiment, the graphene-oxide composite electrode is synthesized via a modified Hummers' method followed by electrochemical reduction. The resulting electrode exhibits a highly porous macroscopic structure with a surface area exceeding 800 m2/g.")
add_paragraph("The reaction chamber is configured to maintain a continuous flow of contaminated water between the anode and cathode. The electrode gap distance is critical for optimizing mass transfer and minimizing ohmic drop across the aqueous solution.")
add_paragraph("During operation, a direct current is applied across the electrodes. The applied voltage is preferably maintained between 2.0 V and 4.5 V, depending on the conductivity of the influent water. This potential range is sufficient to generate hydroxyl radicals without excessive oxygen evolution.")
add_paragraph("A continuous recirculation subsystem may be fluidly coupled to the reaction chamber to ensure multiple passes of the aqueous solution, further enhancing the removal efficiency of recalcitrant contaminants.")
add_paragraph("It will be appreciated by those skilled in the art that various modifications and variations can be made to the embodiments described herein without departing from the spirit or scope of the invention.")
add_paragraph("")

add_paragraph("Claims")
add_paragraph("A system for electrochemical water purification comprising a reaction chamber, an anode, a cathode, and a power supply, wherein at least one of the anode or cathode comprises a graphene-oxide composite.")
add_paragraph("The system of claim 1, wherein the electrode gap distance is between 1.0 mm and 5.0 mm.")
add_paragraph("The system of claim 1, wherein the graphene-oxide composite comprises between 2% and 15% transition metal nanoparticles by weight.")
add_paragraph("The system of claim 1, further comprising a recirculation subsystem fluidly coupled to the reaction chamber.")
add_paragraph("A method for purifying water using an electrochemical system, comprising the steps of introducing contaminated water into a reaction chamber, applying a direct current across a graphene-oxide composite anode and a cathode, and continuously recirculating the water.")
add_paragraph("The method of claim 5, wherein the applied direct current maintains a voltage range between 2.0 V and 4.5 V.")
add_paragraph("The method of claim 5, wherein the water is introduced at a flow rate of between 10 L/min and 50 L/min.")
add_paragraph("The method of claim 5, further comprising the step of monitoring the conductivity of the water to automatically adjust the applied direct current.")
add_paragraph("")

add_paragraph("Abstract")
add_paragraph("A system and method for electrochemical water purification utilizing graphene-oxide composite electrodes. The system includes a reaction chamber housing an anode and a cathode, where at least one electrode features a porous graphene-oxide matrix. By applying a specific voltage range, the system generates reactive species that efficiently degrade organic contaminants and remove heavy metals without suffering from rapid membrane fouling or passivation. A recirculation subsystem ensures optimal contact time for complete water treatment.")

doc.save("/home/ga/Documents/patent_application.odt")
PYEOF

chown ga:ga /home/ga/Documents/patent_application.odt

# Launch Calligra Words with the document
echo "Launching Calligra Words..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid calligrawords /home/ga/Documents/patent_application.odt > /tmp/calligra_launch.log 2>&1 < /dev/null &"

# Wait for window and maximize
WID=""
for i in {1..20}; do
    if DISPLAY=:1 wmctrl -l | grep -i "patent_application"; then
        WID=$(DISPLAY=:1 wmctrl -l | grep -i "patent_application" | awk '{print $1}')
        break
    fi
    sleep 1
done

if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    # Ensure it's active
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Setup Complete ==="