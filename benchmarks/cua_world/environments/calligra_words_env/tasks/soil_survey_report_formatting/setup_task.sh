#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Soil Survey Report Formatting Task ==="

# Record task start time
date +%s > /tmp/task_start_time

kill_calligra_processes

install -d -o ga -g ga /home/ga/Documents
rm -f /home/ga/Documents/soil_survey_report.odt

# ------------------------------------------------------------------
# Create the unformatted Soil Survey report using odfpy
# ALL content is plain P elements — no heading styles, no tables,
# no bold — everything is plain paragraphs.
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# ── Title page elements ──
add_paragraph("Soil Survey and Management Assessment")
add_paragraph("Story County, Iowa - Parcel 84-12A")
add_paragraph("Prepared by: Sarah Jenkins, Lead Soil Scientist")
add_paragraph("Date: May 12, 2026")
add_paragraph("USDA Natural Resources Conservation Service")
add_paragraph("")

# ── Executive Summary ──
add_paragraph("Executive Summary")
add_paragraph("A comprehensive soil survey and pedological assessment was conducted for the 160-acre agricultural parcel (84-12A) located in Story County, Iowa. The assessment included field morphological descriptions, soil sampling, and laboratory analysis to determine current fertility status, soil taxonomy, and optimal management practices. The dominant soil type identified is the Clarion series, a well-drained, fine-loamy soil typical of the Des Moines Lobe. Laboratory results indicate slightly acidic topsoil (pH 5.9) with adequate organic matter (3.8%) but depleted exchangeable potassium. Recommendations include targeted lime application and a revised nutrient management plan to support a corn-soybean rotation while minimizing nutrient runoff.")
add_paragraph("")

# ── Site Description and Land Use History ──
add_paragraph("Site Description and Land Use History")
add_paragraph("The subject parcel is located in Story County, characterized by undulating till plains of the Clarion-Nicollet-Webster soil association. The site has a 2-5% slope, generally draining towards the southeast into the Skunk River watershed. Historical aerial imagery and landowner records indicate the parcel has been in continuous conventional-tillage agricultural production for at least 60 years, primarily under a corn-soybean rotation. Subsurface tile drainage was installed in the lower depressional areas approximately 25 years ago.")
add_paragraph("")

# ── Soil Profile Descriptions ──
add_paragraph("Soil Profile Descriptions")
add_paragraph("Soil cores were extracted using a hydraulic probe to a depth of 120 cm at three representative locations across the parcel. The following morphological description represents the modal profile for the Clarion loam mapping unit.")
add_paragraph("")

add_paragraph("Ap Horizon (0-28 cm)")
add_paragraph("Very dark grayish brown (10YR 3/2) loam; weak fine granular structure; friable consistence; common fine roots; abrupt smooth boundary.")
add_paragraph("")

add_paragraph("Bt1 Horizon (28-56 cm)")
add_paragraph("Dark yellowish brown (10YR 4/4) clay loam; moderate medium subangular blocky structure; firm consistence; thin patchy clay films on faces of peds; clear smooth boundary.")
add_paragraph("")

add_paragraph("Bt2 Horizon (56-91 cm)")
add_paragraph("Yellowish brown (10YR 5/4) silty clay loam; common fine distinct strong brown (7.5YR 5/6) redoximorphic concentrations; weak coarse subangular blocky structure; firm consistence; gradual wavy boundary.")
add_paragraph("")

add_paragraph("Table 1: Morphological Properties Summary")
add_paragraph("Horizon | Depth (cm) | Munsell Color | Texture Class | Structure | pH")
add_paragraph("Ap | 0-28 | 10YR 3/2 | Loam | Weak granular | 5.9")
add_paragraph("Bt1 | 28-56 | 10YR 4/4 | Clay Loam | Mod. subangular blocky | 6.2")
add_paragraph("Bt2 | 56-91 | 10YR 5/4 | Silty Clay Loam | Weak subangular blocky | 6.5")
add_paragraph("C | 91-120+ | 2.5Y 6/4 | Loam | Massive | 7.1")
add_paragraph("")

# ── Chemical and Physical Analysis Results ──
add_paragraph("Chemical and Physical Analysis Results")
add_paragraph("Composite soil samples from the Ap horizon (0-20 cm) were submitted to the AgTest Laboratory for standard agronomic analysis. The results indicate a need for pH correction and potassium supplementation.")
add_paragraph("")

add_paragraph("Macronutrient and pH Analysis")
add_paragraph("Soil pH is currently 5.9, which is below the optimal range of 6.0-6.5 for a corn-soybean rotation, potentially limiting macronutrient availability. The buffer pH of 6.4 indicates a moderate lime requirement. Olsen Phosphorus levels are adequate, but exchangeable Potassium is in the 'low' category.")
add_paragraph("")

add_paragraph("Micronutrient and Physical Properties")
add_paragraph("Cation Exchange Capacity (CEC) is measured at 24.5 meq/100g, reflecting the smectitic mineralogy and good organic matter content (3.8%). Base saturation is dominated by calcium (68%), with magnesium at 15% and potassium deficient at 1.8%.")
add_paragraph("")

add_paragraph("Table 2: Soil Chemical Properties (Ap Horizon)")
add_paragraph("Parameter | Measured Value | Optimal Range | Status")
add_paragraph("Soil pH (1:1 water) | 5.9 | 6.0 - 6.5 | Low")
add_paragraph("Organic Matter (%) | 3.8 | > 3.0 | Optimal")
add_paragraph("Olsen P (ppm) | 22.0 | 16 - 25 | Optimal")
add_paragraph("Exchangeable K (ppm) | 115.0 | 160 - 200 | Low")
add_paragraph("CEC (meq/100g) | 24.5 | 15 - 30 | Optimal")
add_paragraph("")

# ── Soil Classification and Taxonomy ──
add_paragraph("Soil Classification and Taxonomy")
add_paragraph("Based on the morphological description and laboratory data, the soil is classified according to USDA Soil Taxonomy as a Fine-loamy, mixed, superactive, mesic Typic Argiudoll. The presence of a dark, organic-rich mollic epipedon (Ap horizon) over an argillic horizon (Bt horizons) with high base saturation confirms the classification as an Argiudoll. This soil is considered prime farmland when adequately drained and managed.")
add_paragraph("")

# ── Management Recommendations ──
add_paragraph("Management Recommendations")
add_paragraph("Management practices should focus on building soil pH, correcting the potassium deficiency, and implementing conservation practices to prevent erosion on the 2-5% slopes.")
add_paragraph("")

add_paragraph("Table 3: Agronomic Management Action Plan")
add_paragraph("Practice | Priority | Timeline | Expected Outcome")
add_paragraph("Ag Lime Application (2.5 tons/ac) | High | Fall 2026 | Raise pH to 6.5, improve nutrient availability")
add_paragraph("Potash Application (120 lbs K2O/ac) | High | Spring 2027 | Correct K deficiency, improve stalk strength")
add_paragraph("Transition to No-Till | Medium | 2027-2028 | Reduce erosion, increase organic matter retention")
add_paragraph("Cover Crop (Cereal Rye) | Low | Fall 2028 | Scavenge residual nitrogen, improve soil structure")
add_paragraph("")

# ── Appendix: Methods and Standards ──
add_paragraph("Appendix: Methods and Standards")
add_paragraph("Field descriptions follow the National Soil Survey Handbook (NSSH) and the Field Book for Describing and Sampling Soils (Version 3.0). Munsell soil colors were determined using moist soil samples. Laboratory analyses were performed in accordance with the Soil Survey Laboratory Methods Manual (SSIR No. 42).")

doc.save("/home/ga/Documents/soil_survey_report.odt")
PYEOF

chown ga:ga /home/ga/Documents/soil_survey_report.odt

# Launch Calligra Words
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid calligrawords /home/ga/Documents/soil_survey_report.odt > /tmp/calligra_task.log 2>&1 < /dev/null &"

# Wait for application window to appear and maximize it
wait_for_window "Calligra Words" 30
sleep 2
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot showing the unformatted text
sleep 2
take_screenshot /tmp/task_initial_state.png ga

echo "=== Task Setup Complete ==="