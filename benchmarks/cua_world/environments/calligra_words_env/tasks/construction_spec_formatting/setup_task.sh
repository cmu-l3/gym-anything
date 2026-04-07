#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Construction Spec Formatting Task ==="

kill_calligra_processes

install -d -o ga -g ga /home/ga/Documents

rm -f /home/ga/Documents/concrete_specification.odt

# Generate the raw specification document using Python and odfpy
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add(t):
    doc.text.addElement(P(text=t))

add("SECTION 03 30 00 - CAST-IN-PLACE CONCRETE")
add("")
add("PART 1 - GENERAL")
add("")
add("1.1 SUMMARY")
add("A. This Section specifies cast-in place concrete, including formwork, reinforcement, concrete materials, mixture design, placement procedures, and finishes.")
add("B. Related Requirements: Section 31 20 00 Earth Moving for drainage fill under slabs-on-grade.")
add("")
add("1.2 SUBMITTALS")
add("A. Product Data: For each type of product.")
add("B. Design Mixtures: For each concrete mixture. Submit alternate design mixtures when characteristics of materials, project conditions, weather, test results, or other circumstances warrant adjustments.")
add("C. Steel Reinforcement Shop Drawings: Placing Drawings that detail fabrication, bending, and placement.")
add("")
add("1.3 QUALITY ASSURANCE")
add("A. Installer Qualifications: A qualified installer who employs on Project personnel qualified as ACI-certified Flatwork Technician and Finisher and a supervisor who is an ACI-certified Concrete Flatwork Technician.")
add("B. Manufacturer Qualifications: A firm experienced in manufacturing ready-mixed concrete products and that complies with ASTM C 94/C 94M requirements for production facilities and equipment.")
add("")
add("1.4 DELIVERY, STORAGE, AND HANDLING")
add("A. Steel Reinforcement: Deliver, store, and handle steel reinforcement to prevent bending and damage.")
add("")
add("PART 2 - PRODUCTS")
add("")
add("2.1 CONCRETE MATERIALS")
add("A. Cementitious Materials: Portland Cement: ASTM C 150/C 150M, Type I/II, gray.")
add("B. Normal-Weight Aggregates: ASTM C 33/C 33M, graded.")
add("C. Water: ASTM C 94/C 94M and potable.")
add("")
add("2.2 ADMIXTURES")
add("A. Air-Entraining Admixture: ASTM C 260/C 260M.")
add("B. Chemical Admixtures: Certified by manufacturer to be compatible with other admixtures and that do not contribute water-soluble chloride ions exceeding those permitted in hardened concrete. Do not use calcium chloride or admixtures containing calcium chloride.")
add("C. Water-Reducing Admixture: ASTM C 494/C 494M, Type A.")
add("")
add("2.3 CURING MATERIALS")
add("A. Evaporation Retarder: Waterborne, monomolecular film forming, manufactured for application to fresh concrete.")
add("B. Absorptive Cover: AASHTO M 182, Class 2, burlap cloth made from jute or kenaf, weighing approximately 9 oz./sq. yd. when dry.")
add("")
add("2.4 RELATED MATERIALS")
add("A. Expansion-and-Isolation-Joint-Filler Strips: ASTM D 1751, asphalt-saturated cellulosic fiber.")
add("")
add("PART 3 - EXECUTION")
add("")
add("3.1 PREPARATION")
add("A. Formwork: Design, erect, shore, brace, and maintain formwork, according to ACI 301, to support vertical, lateral, static, and dynamic loads, and construction loads that might be applied, until structure can support such loads.")
add("B. Reinforcement: Comply with CRSI's Manual of Standard Practice for fabricating, placing, and supporting reinforcement.")
add("")
add("3.2 PLACING CONCRETE")
add("A. Before placing concrete, verify that installation of formwork, reinforcement, and embedded items is complete and that required inspections are completed.")
add("B. Deposit concrete continuously in one layer or in horizontal layers of such thickness that no new concrete is placed on concrete that has hardened enough to cause seams or planes of weakness.")
add("")
add("3.3 FINISHING")
add("A. General: Comply with ACI 302.1R recommendations for screeding, restraightening, and finishing operations for concrete surfaces.")
add("B. Trowel Finish: After applying float finish, apply first troweling and consolidate concrete by hand or power-driven trowel. Continue troweling passes and restraighten until surface is free of trowel marks and uniform in texture and appearance.")
add("")
add("3.4 CONCRETE PROTECTING AND CURING")
add("A. General: Protect freshly placed concrete from premature drying and excessive cold or hot temperatures. Comply with ACI 306.1 for cold-weather protection and ACI 301 for hot-weather protection during placement.")
add("B. Evaporation Retarder: Apply evaporation retarder to unformed concrete surfaces if hot, dry, or windy conditions cause moisture loss approaching 0.2 lb/sq. ft. x h before and during finishing operations.")

doc.save("/home/ga/Documents/concrete_specification.odt")
PYEOF

chown ga:ga /home/ga/Documents/concrete_specification.odt

# Record timestamps for anti-gaming verification
date +%s > /tmp/task_start_time.txt
stat -c %Y /home/ga/Documents/concrete_specification.odt > /tmp/initial_mtime.txt

# Launch Calligra Words with the document
launch_calligra_document "/home/ga/Documents/concrete_specification.odt"
sleep 5

# Ensure Window is correctly focused and maximized
wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="