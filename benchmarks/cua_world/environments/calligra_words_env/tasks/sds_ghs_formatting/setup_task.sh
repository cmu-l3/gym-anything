#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up SDS GHS Formatting Task ==="

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop
kill_calligra_processes

rm -f /home/ga/Documents/sds_isopropanol.odt
rm -f /home/ga/Desktop/ghs_formatting_guide.txt

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create the formatting guide
cat > /home/ga/Desktop/ghs_formatting_guide.txt << 'EOF'
GHS SAFETY DATA SHEET (SDS) FORMATTING REQUIREMENTS
---------------------------------------------------
To comply with OSHA 29 CFR 1910.1200 and GHS Rev. 9, the SDS must be formatted as follows:

1. SECTION HEADINGS: All 16 primary GHS sections MUST be formatted as Heading 1.
   (e.g., "1. Identification", "2. Hazard(s) Identification", etc.)

2. SUBSECTION HEADINGS: Any sub-headings within the 16 sections MUST be formatted as Heading 2.

3. SIGNAL WORD: The signal word (e.g., "DANGER" or "WARNING") in Section 2 MUST be formatted in BOLD text with a font size of at least 16pt.

4. HAZARD CODES: All GHS Hazard statements (H-codes like H225, H319) MUST be in BOLD text where they appear in the document.

5. TABLES: Physical/Chemical Properties (Section 9) and/or Toxicological Data (Section 11) must be formatted as proper tables, not plain text.

6. TABLE OF CONTENTS: A Table of Contents must be inserted at the beginning of the document (after the title).

7. BODY TEXT: All standard body paragraphs MUST be Justified alignment.

Note: Do not delete any critical chemical data or values while formatting.
EOF

chown ga:ga /home/ga/Desktop/ghs_formatting_guide.txt

# Create the unformatted ODT file
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# Title
add_paragraph("SAFETY DATA SHEET")
add_paragraph("Isopropyl Alcohol, 99%")
add_paragraph("")

add_paragraph("1. Identification")
add_paragraph("Product Name: Isopropyl Alcohol, 99%")
add_paragraph("CAS Number: 67-63-0")
add_paragraph("Recommended Use: Laboratory chemical, solvent, cleaning agent")
add_paragraph("Supplier: ChemCorp Industries, 100 Science Way, Research City, CA 90210")
add_paragraph("Emergency Phone: 1-800-555-0199")
add_paragraph("")

add_paragraph("2. Hazard(s) Identification")
add_paragraph("GHS Classification: Flammable liquids (Category 2), Eye irritation (Category 2A), Specific target organ toxicity - single exposure (Category 3, Central nervous system)")
add_paragraph("Signal Word: DANGER")
add_paragraph("Hazard Statements: H225 Highly flammable liquid and vapor. H319 Causes serious eye irritation. H336 May cause drowsiness or dizziness.")
add_paragraph("Precautionary Statements: P210 Keep away from heat/sparks/open flames/hot surfaces. No smoking. P233 Keep container tightly closed. P240 Ground/bond container and receiving equipment. P261 Avoid breathing dust/fume/gas/mist/vapors/spray. P280 Wear protective gloves/protective clothing/eye protection/face protection. P303+P361+P353 IF ON SKIN (or hair): Take off immediately all contaminated clothing. Rinse skin with water/shower. P305+P351+P338 IF IN EYES: Rinse cautiously with water for several minutes. Remove contact lenses, if present and easy to do. Continue rinsing. P370+P378 In case of fire: Use dry sand, dry chemical or alcohol-resistant foam to extinguish. P403+P235 Store in a well-ventilated place. Keep cool. P501 Dispose of contents/container to an approved waste disposal plant.")
add_paragraph("")

add_paragraph("3. Composition/Information on Ingredients")
add_paragraph("Chemical Identity: Isopropyl Alcohol")
add_paragraph("Common Name: Isopropanol, 2-Propanol")
add_paragraph("CAS Number: 67-63-0")
add_paragraph("Concentration: >= 99.0%")
add_paragraph("")

add_paragraph("4. First-Aid Measures")
add_paragraph("General advice: Consult a physician. Show this safety data sheet to the doctor in attendance.")
add_paragraph("If inhaled: If breathed in, move person into fresh air. If not breathing, give artificial respiration.")
add_paragraph("In case of skin contact: Wash off with soap and plenty of water.")
add_paragraph("In case of eye contact: Rinse thoroughly with plenty of water for at least 15 minutes.")
add_paragraph("If swallowed: Do NOT induce vomiting. Never give anything by mouth to an unconscious person. Rinse mouth with water.")
add_paragraph("")

add_paragraph("5. Fire-Fighting Measures")
add_paragraph("Suitable extinguishing media: Use water spray, alcohol-resistant foam, dry chemical or carbon dioxide.")
add_paragraph("Special hazards arising from the substance: Carbon oxides")
add_paragraph("Advice for firefighters: Wear self-contained breathing apparatus for firefighting if necessary.")
add_paragraph("")

add_paragraph("6. Accidental Release Measures")
add_paragraph("Personal precautions: Use personal protective equipment. Avoid breathing vapors, mist or gas. Ensure adequate ventilation. Remove all sources of ignition.")
add_paragraph("Environmental precautions: Prevent further leakage or spillage if safe to do so. Do not let product enter drains.")
add_paragraph("Methods and materials for containment and cleaning up: Contain spillage, and then collect with non-combustible absorbent material and place in container for disposal.")
add_paragraph("")

add_paragraph("7. Handling and Storage")
add_paragraph("Precautions for safe handling: Avoid contact with skin and eyes. Avoid inhalation of vapor or mist. Keep away from sources of ignition - No smoking. Take measures to prevent the buildup of electrostatic charge.")
add_paragraph("Conditions for safe storage: Keep container tightly closed in a dry and well-ventilated place. Containers which are opened must be carefully resealed and kept upright to prevent leakage.")
add_paragraph("")

add_paragraph("8. Exposure Controls/Personal Protection")
add_paragraph("Control Parameters")
add_paragraph("OSHA PEL: 400 ppm (980 mg/m3) TWA")
add_paragraph("ACGIH TLV: 200 ppm TWA, 400 ppm STEL")
add_paragraph("Exposure Controls")
add_paragraph("Engineering controls: Handle in accordance with good industrial hygiene and safety practice. Wash hands before breaks and at the end of workday.")
add_paragraph("Personal protective equipment: Safety glasses with side-shields, flame retardant antistatic protective clothing, nitrile rubber gloves.")
add_paragraph("")

add_paragraph("9. Physical and Chemical Properties")
add_paragraph("Property | Value")
add_paragraph("Appearance | Clear, colorless liquid")
add_paragraph("Odor | Alcohol-like")
add_paragraph("pH | No data available")
add_paragraph("Melting point | -89.5 °C")
add_paragraph("Boiling point | 82.6 °C")
add_paragraph("Flash point | 11.7 °C (Closed Cup)")
add_paragraph("Evaporation rate | 3.0")
add_paragraph("Flammability | Highly flammable")
add_paragraph("Vapor pressure | 43.2 hPa at 20.0 °C")
add_paragraph("Vapor density | 2.07 (Air = 1.0)")
add_paragraph("Relative density | 0.786 g/cm3 at 20 °C")
add_paragraph("Water solubility | Completely soluble")
add_paragraph("Auto-ignition temperature | 399 °C")
add_paragraph("Decomposition temperature | No data available")
add_paragraph("Viscosity | 2.1 mPa.s at 25 °C")
add_paragraph("")

add_paragraph("10. Stability and Reactivity")
add_paragraph("Reactivity: No data available")
add_paragraph("Chemical stability: Stable under recommended storage conditions.")
add_paragraph("Possibility of hazardous reactions: Vapors may form explosive mixture with air.")
add_paragraph("Conditions to avoid: Heat, flames and sparks.")
add_paragraph("Incompatible materials: Oxidizing agents, Acid anhydrides, Aluminium, Halogenated compounds, Acids.")
add_paragraph("")

add_paragraph("11. Toxicological Information")
add_paragraph("Route | Species | Value")
add_paragraph("LD50 Oral | Rat | 5045 mg/kg")
add_paragraph("LC50 Inhalation | Rat | 72.6 mg/L (4h)")
add_paragraph("LD50 Dermal | Rabbit | 12800 mg/kg")
add_paragraph("")

add_paragraph("12. Ecological Information")
add_paragraph("Toxicity to fish: LC50 - Pimephales promelas (fathead minnow) - 9,640 mg/l - 96 h")
add_paragraph("Toxicity to daphnia: EC50 - Daphnia magna (Water flea) - 5,102 mg/l - 24 h")
add_paragraph("Persistence and degradability: Readily biodegradable.")
add_paragraph("Bioaccumulative potential: No bioaccumulation is to be expected (log Pow <= 4).")
add_paragraph("")

add_paragraph("13. Disposal Considerations")
add_paragraph("Waste treatment methods: Burn in a chemical incinerator equipped with an afterburner and scrubber but exert extra care in igniting as this material is highly flammable. Offer surplus and non-recyclable solutions to a licensed disposal company.")
add_paragraph("")

add_paragraph("14. Transport Information")
add_paragraph("DOT (US)")
add_paragraph("UN number: 1219")
add_paragraph("Class: 3")
add_paragraph("Packing group: II")
add_paragraph("Proper shipping name: Isopropanol")
add_paragraph("Reportable Quantity (RQ): None")
add_paragraph("Poison Inhalation Hazard: No")
add_paragraph("")

add_paragraph("15. Regulatory Information")
add_paragraph("SARA 302 Components: No chemicals in this material are subject to the reporting requirements of SARA Title III, Section 302.")
add_paragraph("SARA 313 Components: The following components are subject to reporting levels established by SARA Title III, Section 313: 2-Propanol (CAS 67-63-0).")
add_paragraph("SARA 311/312 Hazards: Fire Hazard, Acute Health Hazard, Chronic Health Hazard.")
add_paragraph("Massachusetts Right To Know Components: 2-Propanol")
add_paragraph("Pennsylvania Right To Know Components: 2-Propanol")
add_paragraph("New Jersey Right To Know Components: 2-Propanol")
add_paragraph("California Prop. 65 Components: This product does not contain any chemicals known to State of California to cause cancer, birth defects, or any other reproductive harm.")
add_paragraph("")

add_paragraph("16. Other Information")
add_paragraph("HMIS Rating")
add_paragraph("Health hazard: 2")
add_paragraph("Chronic Health Hazard: *")
add_paragraph("Flammability: 3")
add_paragraph("Physical Hazard: 0")
add_paragraph("Revision Date: 10/12/2025")
add_paragraph("Disclaimer: The information above is believed to be accurate and represents the best information currently available to us. However, we make no warranty of merchantability or any other warranty, express or implied, with respect to such information.")

doc.save("/home/ga/Documents/sds_isopropanol.odt")
PYEOF

chown ga:ga /home/ga/Documents/sds_isopropanol.odt

# Launch Calligra Words
launch_calligra_document "/home/ga/Documents/sds_isopropanol.odt" "/tmp/calligra.log"

# Wait for window and maximize
WID=""
for i in {1..30}; do
    WID=$(get_calligra_window_id)
    if [ -n "$WID" ]; then
        break
    fi
    sleep 1
done

if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    # Dismiss any startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    focus_window "$WID"
fi

take_screenshot /tmp/task_initial_state.png
echo "=== Setup complete ==="