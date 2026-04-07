#!/bin/bash
set -euo pipefail

echo "=== Setting up CRM Archaeology Report Task ==="

# Source utility functions
source /workspace/scripts/task_utils.sh || true

# Set up environment variables
export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}

# Create required directories
sudo -u ga mkdir -p /home/ga/Documents/results
sudo -u ga mkdir -p /home/ga/Desktop

# Generate the raw document using Python and python-docx
python3 << 'PYEOF'
import os
from docx import Document
from docx.shared import Pt

def create_raw_doc():
    doc = Document()

    # Plain unformatted title
    doc.add_paragraph("Phase I Archaeological Survey of the Proposed Route 47 Expansion Project")
    doc.add_paragraph("")

    doc.add_paragraph("1.0 INTRODUCTION")
    doc.add_paragraph("This report presents the findings of a Phase I archaeological survey for the proposed Route 47 Expansion Project in Greenville County. The Area of Potential Effects (APE) consists of a 4.2-mile linear corridor comprising approximately 52 acres of new right-of-way.")

    doc.add_paragraph("2.0 ENVIRONMENTAL SETTING")
    doc.add_paragraph("The project area is located within the Piedmont physiographic province. Soils are predominantly Cecil sandy loams, well-drained and heavily eroded from historic agricultural practices. The local overstory is dominated by loblolly pine (Pinus taeda) and white oak (Quercus alba). Fauna commonly observed in the area includes white-tailed deer (Odocoileus virginianus) and wild turkey (Meleagris gallopavo).")

    doc.add_paragraph("3.0 CULTURAL CONTEXT")
    doc.add_paragraph("Human occupation in the region spans at least 12,000 years, beginning with the Paleoindian period. The area saw intense historic European settlement beginning in the late 18th century, primarily characterized by small agrarian farmsteads transitioning to cotton agriculture by the mid-19th century.")

    doc.add_paragraph("4.0 FIELD METHODS")
    doc.add_paragraph("Pedestrian survey was conducted across all areas of >15% surface visibility. Subsurface testing consisted of Shovel Test Pits (STPs) excavated at 15-meter intervals along three parallel transects. All excavated soils were screened through 1/4-inch hardware mesh.")

    doc.add_paragraph("5.0 RESULTS")
    doc.add_paragraph("Fieldwork was conducted from October 12-14, 2024. A total of 8 STPs were excavated across three transects. One new archaeological site (31GV284) was identified, represented by a sparse historic artifact scatter.")
    doc.add_paragraph("")
    doc.add_paragraph("Shovel Test Pit Log:")
    doc.add_paragraph("Transect | STP No. | Depth (cm) | Stratigraphy | Cultural Material")
    doc.add_paragraph("TR-1 | 1 | 0-10 | 10YR 3/4 silt loam | None")
    doc.add_paragraph("TR-1 | 2 | 0-15 | 10YR 4/4 silty clay | 1 quartz flake")
    doc.add_paragraph("TR-1 | 3 | 0-12 | 10YR 4/6 clay | None")
    doc.add_paragraph("TR-2 | 1 | 0-10 | 10YR 3/4 silt loam | 2 brick fragments")
    doc.add_paragraph("TR-2 | 2 | 0-18 | 10YR 4/4 silty clay | 1 whiteware sherd")
    doc.add_paragraph("TR-2 | 3 | 0-15 | 10YR 4/6 clay | None")
    doc.add_paragraph("TR-3 | 1 | 0-20 | 10YR 3/4 silt loam | 1 window glass fragment")
    doc.add_paragraph("TR-3 | 2 | 0-12 | 10YR 4/4 silty clay | None")
    doc.add_paragraph("")
    doc.add_paragraph("Artifact Catalog:")
    doc.add_paragraph("Catalog No. | Context | Count | Material | Description")
    doc.add_paragraph("001 | TR-1, STP 2 | 1 | Lithic | Quartz secondary flake")
    doc.add_paragraph("002 | TR-2, STP 1 | 2 | Ceramic | Handmade brick fragments")
    doc.add_paragraph("003 | TR-2, STP 2 | 1 | Ceramic | Undecorated whiteware sherd")
    doc.add_paragraph("004 | TR-3, STP 1 | 1 | Glass | Aqua window glass")

    doc.add_paragraph("6.0 SUMMARY AND RECOMMENDATIONS")
    doc.add_paragraph("Site 31GV284 lacks intact subsurface cultural features and possesses a low artifact density. It is not considered eligible for the National Register of Historic Places (NRHP). No further archaeological work is recommended for the proposed Route 47 Expansion Project corridor.")

    doc.add_paragraph("7.0 REFERENCES CITED")
    doc.add_paragraph("Coe, Joffre L. 1964. The Formative Cultures of the Carolina Piedmont. Transactions of the American Philosophical Society 54(5). Philadelphia.")
    doc.add_paragraph("South, Stanley. 1977. Method and Theory in Historical Archaeology. Academic Press, New York.")
    doc.add_paragraph("Trinkley, Michael. 1990. An Archaeological Context for the South Carolina Woodland Period. Chicora Foundation Research Series 22, Columbia.")

    output_path = "/home/ga/Documents/raw_phase_i_survey.docx"
    doc.save(output_path)
    os.system(f"chown ga:ga {output_path}")

create_raw_doc()
PYEOF

# Record task start time
date +%s > /tmp/task_start_time.txt

# Start WPS Writer and open the document
if ! pgrep -f "wps" > /dev/null; then
    echo "Starting WPS Writer..."
    sudo -u ga DISPLAY=:1 wps /home/ga/Documents/raw_phase_i_survey.docx &
    sleep 5
fi

# Wait for window and maximize it
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "WPS Writer"; then
        echo "WPS window detected"
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r "WPS Writer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "WPS Writer" 2>/dev/null || true

# Handle EULA or First-run dialogs if they pop up
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="