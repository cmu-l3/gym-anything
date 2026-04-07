#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Archaeological Site Report Formatting Task ==="

kill_calligra_processes

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop
install -d -o ga -g ga /home/ga/Desktop/Field_Photos

rm -f /home/ga/Documents/site_report_draft.odt
rm -f /home/ga/Desktop/formatting_requirements.txt

# ------------------------------------------------------------------
# Create dummy field photos (valid PNG files with .png extension)
# ------------------------------------------------------------------
echo "iVBORw0KGgoAAAANSUhEUgAAAAoAAAAKCAYAAACNMs+9AAAAFUlEQVR42mP8z8BQz0AEYBxVSF+FAP5E/wH0V1KRAAAAAElFTkSuQmCC" | base64 -d > /home/ga/Desktop/Field_Photos/site_map.png
echo "iVBORw0KGgoAAAANSUhEUgAAAAoAAAAKCAYAAACNMs+9AAAAFUlEQVR42mNk+M9QDwEYRxVSF+FAP5E/wE2aE2MAAAAASUVORK5CYII=" | base64 -d > /home/ga/Desktop/Field_Photos/stratigraphy.png
echo "iVBORw0KGgoAAAANSUhEUgAAAAoAAAAKCAYAAACNMs+9AAAAFUlEQVR42mNkYPhfDwEYRxVSF+FAP5E/wG/wX+gAAAAASUVORK5CYII=" | base64 -d > /home/ga/Desktop/Field_Photos/projectile_points.png
chown -R ga:ga /home/ga/Desktop/Field_Photos

# ------------------------------------------------------------------
# Write formatting requirements
# ------------------------------------------------------------------
cat << 'EOF' > /home/ga/Desktop/formatting_requirements.txt
Archaeological Site Report Formatting Instructions

1. Headings:
   Apply "Heading 1" to the 5 main sections:
   - Introduction
   - Stratigraphic Context
   - Artifact Assemblage
   - Chronometric Dating
   - Conclusions

   Apply "Heading 2" to the 4 subsections under Artifact Assemblage:
   - Lithics
   - Ceramics
   - Faunal Remains
   - Archaeobotanical Remains

2. Images:
   Insert the 3 images found in ~/Desktop/Field_Photos/ into their relevant sections in the report.

3. Data Table:
   In the "Chronometric Dating" section, there is raw radiocarbon data formatted as plain text.
   Create a 3-column table and move the raw data (Sample ID, Material, Age BP) into the table cells.
   Make the header row of the table Bold.

4. Biological Taxa:
   Find the following scientific names in the text and format them with Italics:
   - Zea mays
   - Phaseolus vulgaris
   - Odocoileus hemionus
   - Meleagris gallopavo
EOF
chown ga:ga /home/ga/Desktop/formatting_requirements.txt

# ------------------------------------------------------------------
# Create the unformatted Site Report using odfpy
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

add_paragraph("Site 42WN34 Excavation Report")
add_paragraph("")

add_paragraph("Introduction")
add_paragraph("Excavations at site 42WN34 revealed a multi-component occupation spanning the late Archaic through the Formative periods. The primary objective of the 2025 field season was to define the spatial extent of the residential architecture and recover diagnostic artifacts to establish a chronological framework.")
add_paragraph("")

add_paragraph("Stratigraphic Context")
add_paragraph("The site stratigraphy consists of four primary depositional units. Stratum I is a loose eolian sand containing mixed modern and historical debris. Stratum II represents the primary cultural deposit, characterized by a dark, organically rich anthropogenic soil. Below this, Stratum III is a culturally sterile alluvial deposit, resting on the Stratum IV bedrock.")
add_paragraph("")

add_paragraph("Artifact Assemblage")
add_paragraph("The artifact assemblage recovered from Stratum II provides insight into the domestic and subsistence activities of the site's inhabitants.")
add_paragraph("")

add_paragraph("Lithics")
add_paragraph("The chipped stone assemblage is dominated by locally available chert and obsidian sourced from the Mineral Mountains. Formal tools include 14 Desert Side-notched projectile points, 8 bifacial knives, and numerous expedient flake tools.")
add_paragraph("")

add_paragraph("Ceramics")
add_paragraph("Ceramic sherds recovered from the site include a mix of corrugated utility wares and decorated black-on-white bowls. The dominance of Sevier Gray ware suggests strong affiliations with the broader Fremont cultural complex.")
add_paragraph("")

add_paragraph("Faunal Remains")
add_paragraph("The faunal assemblage indicates a reliance on a mix of large game and localized avian resources. The most abundant identifiable elements belong to mule deer (Odocoileus hemionus) and wild turkey (Meleagris gallopavo), alongside numerous lagomorphs.")
add_paragraph("")

add_paragraph("Archaeobotanical Remains")
add_paragraph("Flotation samples from the central hearth feature yielded direct evidence of agricultural reliance. Carbonized remains of domesticated maize (Zea mays) and common bean (Phaseolus vulgaris) were abundant, alongside wild cheno-am seeds.")
add_paragraph("")

add_paragraph("Chronometric Dating")
add_paragraph("Three radiocarbon samples were submitted for AMS dating to secure the chronology of Stratum II. The raw data should be formatted into a table below:")
add_paragraph("")
add_paragraph("Sample ID | Material | Age BP")
add_paragraph("Beta-12345 | Zea mays | 1250 ± 30")
add_paragraph("Beta-12346 | Wood charcoal | 1310 ± 40")
add_paragraph("Beta-12347 | Bone collagen | 1280 ± 30")
add_paragraph("")

add_paragraph("Conclusions")
add_paragraph("Site 42WN34 represents a significant Ancestral Puebloan habitation site. The combination of agricultural reliance, as evidenced by the archaeobotanical remains, and the robust radiocarbon dates place the primary occupation securely within the Pueblo II period.")

doc.save("/home/ga/Documents/site_report_draft.odt")
PYEOF
chown ga:ga /home/ga/Documents/site_report_draft.odt

# Record task start time
date +%s > /tmp/task_start_time.txt

# Launch Calligra Words
launch_calligra_document "/home/ga/Documents/site_report_draft.odt"
wait_for_window "site_report_draft.odt" 30

# Maximize and focus
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Dismiss startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="