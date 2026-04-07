#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Archeological Site Report Formatting Task ==="

install -d -o ga -g ga /home/ga/Documents
kill_calligra_processes
rm -f /home/ga/Documents/excavation_report_42WN301.odt

# ---------------------------------------------------------------------------
# Create the unformatted Archeological Site Report
# All content is plain P elements — no headings, no tables, no lists
# ---------------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# Title Page Elements
add_paragraph("Excavation Report: Site 42WN301 (Black Creek Ruin)")
add_paragraph("Prepared by: Dr. Sarah Jenkins, Great Basin Archaeological Services")
add_paragraph("Prepared for: State Historic Preservation Office (SHPO)")
add_paragraph("Date: November 12, 2025")
add_paragraph("")

# Section: Introduction
add_paragraph("Introduction")
add_paragraph(
    "Site 42WN301, commonly known as the Black Creek Ruin, is an Ancestral Puebloan "
    "habitation site located in Washington County, Utah. The site is situated on a "
    "terrace overlooking the Santa Clara River at an elevation of approximately 850 "
    "meters above sea level. This report details the findings of the Phase III data "
    "recovery excavations conducted during the summer 2025 field season, which aimed "
    "to mitigate adverse effects prior to the expansion of State Route 9."
)
add_paragraph("")

# Section: Methodology
add_paragraph("Methodology")
add_paragraph(
    "Excavations were conducted using standard archaeological procedures. A permanent "
    "site datum was established, and a 1x1 meter grid system was overlaid on the site. "
    "Test units (TUs) were excavated in 10-centimeter arbitrary levels within natural "
    "stratigraphic layers. All excavated sediments were passed through 1/8-inch "
    "hardware mesh to ensure the recovery of micro-debitage and small faunal remains. "
    "Features were bisected, profiled, and photographed prior to complete removal. "
    "Flotation samples (2 liters each) were collected from all secure cultural contexts "
    "for archaeobotanical analysis."
)
add_paragraph("")

# Section: Stratigraphy & Soils
add_paragraph("Stratigraphy & Soils")
add_paragraph(
    "The site exhibits a relatively straightforward stratigraphic sequence consisting "
    "of two primary strata. Soil colors were recorded using the Munsell Soil Color "
    "Charts under natural light conditions."
)
add_paragraph("Stratum I: Modern surface and eolian deposits (10YR 5/4, yellowish brown)")
add_paragraph("Level 1: 0-10 cmbs, loose sandy loam with heavy root bioturbation")
add_paragraph("Level 2: 10-22 cmbs, moderately compacted sandy loam with sparse gravels")
add_paragraph("Stratum II: Cultural fill and midden (10YR 3/2, very dark grayish brown)")
add_paragraph("Level 3: 22-35 cmbs, silty loam with dense charcoal flecking and ash lenses")
add_paragraph("Level 4: 35-50 cmbs, dense artifact concentration terminating at sterile sterile clay contact")
add_paragraph("")

# Section: Feature Descriptions
add_paragraph("Feature Descriptions")
add_paragraph("Three primary cultural features were identified during the excavation block.")
add_paragraph("")

add_paragraph("Feature 1: Hearth")
add_paragraph(
    "Feature 1 is a circular, basin-shaped hearth identified at the base of Stratum II "
    "(38 cmbs) in TU 4. The feature measures 45 cm in diameter and has a maximum depth "
    "of 12 cm. It was filled with heavily oxidized soil (5YR 4/6) and dense charcoal. "
    "A flotation sample yielded charred Chenopodium seeds and piñon pine fragments."
)
add_paragraph("")

add_paragraph("Feature 2: Midden")
add_paragraph(
    "Feature 2 consists of a concentrated refuse deposit extending across TUs 1 and 2. "
    "The matrix is highly organic and produced the majority of the ceramic and faunal "
    "assemblage recovered from the site. High densities of fire-cracked rock (FCR) "
    "were noted throughout."
)
add_paragraph("")

add_paragraph("Feature 3: Post Hole")
add_paragraph(
    "Feature 3 is a circular post hole measuring 15 cm in diameter, extending 25 cm "
    "into the sterile subsoil in TU 5. The fill contained fragments of decayed juniper "
    "wood, one of which was submitted for radiocarbon dating."
)
add_paragraph("")

# Section: Artifact Catalog
add_paragraph("Artifact Catalog")
add_paragraph("The following represents a summary of the diagnostic artifacts recovered from the site.")
add_paragraph("Catalog # | Unit | Level | Artifact Type | Material | Count | Weight (g)")
add_paragraph("42WN-101 | TU1 | 1 | Lithic Flake | Chert | 12 | 14.5")
add_paragraph("42WN-102 | TU1 | 2 | Desert Side-notched point | Obsidian | 1 | 2.1")
add_paragraph("42WN-103 | TU2 | 3 | Virgin Black-on-white sherd | Ceramic | 4 | 22.8")
add_paragraph("42WN-104 | TU2 | 4 | Groundstone metate fragment | Basalt | 1 | 850.0")
add_paragraph("42WN-105 | TU1 | 3 | Bone awl | Mammal bone | 1 | 8.4")
add_paragraph("42WN-106 | TU4 | Feature 1 | Olivella shell bead | Marine shell | 1 | 0.8")
add_paragraph("")

# Section: Radiocarbon Dating Results
add_paragraph("Radiocarbon Dating Results")
add_paragraph("Three samples were submitted to Beta Analytic for AMS radiocarbon dating.")
add_paragraph("Lab Number | Sample Context | Material | Conventional Radiocarbon Age | Calibrated Date (2-sigma)")
add_paragraph("Beta-489211 | Feature 1 Hearth | Charcoal | 850 +/- 30 BP | AD 1160 - 1225")
add_paragraph("Beta-489212 | Stratum II Level 4 | Charcoal | 920 +/- 30 BP | AD 1040 - 1150")
add_paragraph("Beta-489213 | Feature 3 Post Hole | Wood | 880 +/- 30 BP | AD 1055 - 1210")
add_paragraph("")

# Section: Summary & Conclusions
add_paragraph("Summary & Conclusions")
add_paragraph(
    "The site represents a short-term residential base dating primarily to the late "
    "Pueblo II to early Pueblo III periods (approx. AD 1040-1225). The artifact "
    "assemblage and botanical remains indicate a reliance on both agricultural products "
    "and gathered wild resources. The presence of marine shell (Olivella) suggests "
    "participation in regional exchange networks extending to the Pacific coast. Data "
    "recovery is considered complete, and construction activities will not impact "
    "further intact deposits."
)

doc.save("/home/ga/Documents/excavation_report_42WN301.odt")
PYEOF

chown ga:ga /home/ga/Documents/excavation_report_42WN301.odt

# Launch Calligra Words directly
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority calligrawords /home/ga/Documents/excavation_report_42WN301.odt > /dev/null 2>&1 &"

# Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "excavation_report_42WN301.odt"; then
        WID=$(DISPLAY=:1 wmctrl -l | grep -i "excavation_report_42WN301.odt" | awk '{print $1}')
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
        break
    fi
    sleep 1
done

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial_state.png

echo "=== Setup complete ==="