#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Terminology Standardization Task ==="

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop
kill_calligra_processes
rm -f /home/ga/Documents/clinical_study_report.odt
rm -f /home/ga/Desktop/terminology_glossary.txt

# Create the terminology glossary file on the Desktop
cat > /home/ga/Desktop/terminology_glossary.txt << 'EOF'
TERMINOLOGY GLOSSARY for FDA Submission

Please standardize the following terms throughout the Clinical Study Report. Replace all incorrect variants with the Correct Term exactly as capitalized below.

1. DRUG NAME
Correct Term: Nexapril-XR
Incorrect Variants to Replace:
- nexapril XR
- Nexapril Extended Release
- NXP-XR
- nexapril-xr

2. CONDITION
Correct Term: type 2 diabetes mellitus
Incorrect Variants to Replace:
- Type II Diabetes
- type-2 diabetes
- Type 2 Diabetes Mellitus
- T2D

3. PRIMARY ENDPOINT
Correct Term: HbA1c
Incorrect Variants to Replace:
- hemoglobin A1c
- glycated hemoglobin
- A1C
- Hba1c

4. COMPARATOR
Correct Term: metformin hydrochloride
Incorrect Variants to Replace:
- Metformin hydrochloride
- metformin HCl
- Metformin HCL

5. SPONSOR
Correct Term: Acme Pharmaceuticals, Inc.
Incorrect Variants to Replace:
- AcmePharma
- ACME Pharmaceuticals
- Acme Pharma Inc.
EOF

chown ga:ga /home/ga/Desktop/terminology_glossary.txt

# Generate the ODT draft document using odfpy
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

add_paragraph("Synopsis")
add_paragraph("The sponsor AcmePharma presents the results of the Phase III trial for nexapril XR in patients with Type II Diabetes.")
add_paragraph("The primary endpoint was the reduction in hemoglobin A1c from baseline compared to Metformin hydrochloride.")
add_paragraph("")

add_paragraph("Introduction")
add_paragraph("The condition Type 2 Diabetes Mellitus is a chronic metabolic disorder. The study drug nexapril-xr is developed by ACME Pharmaceuticals to address glycemic control.")
add_paragraph("This clinical study report evaluates the efficacy of NXP-XR versus metformin HCl.")
add_paragraph("")

add_paragraph("Study Objectives")
add_paragraph("Primary Objective")
add_paragraph("To demonstrate the superiority of Nexapril Extended Release in reducing glycated hemoglobin over 24 weeks.")
add_paragraph("Secondary Objectives")
add_paragraph("To assess the safety profile of nexapril XR and its effect on fasting plasma glucose in patients with T2D.")
add_paragraph("")

add_paragraph("Investigational Plan")
add_paragraph("Study Design")
add_paragraph("A randomized, double-blind, placebo-controlled, active-comparator trial with a 2-week washout period.")
add_paragraph("Study Population")
add_paragraph("Patients with Type II Diabetes with inadequate glycemic control after providing informed consent.")
add_paragraph("Treatments Administered")
add_paragraph("Patients received either nexapril-xr 10mg, Metformin HCL 500mg, or matching placebo.")
add_paragraph("")

add_paragraph("Study Patients")
add_paragraph("Disposition of Patients")
add_paragraph("A total of 500 patients were randomized. The intention-to-treat population included 490 patients.")
add_paragraph("Protocol Deviations")
add_paragraph("Minor deviations were noted during the washout period, none affecting the primary efficacy endpoint.")
add_paragraph("")

add_paragraph("Efficacy Evaluation")
add_paragraph("Primary Efficacy Endpoint")
add_paragraph("The primary endpoint, A1C reduction, was statistically significant (95% confidence interval).")
add_paragraph("Secondary Efficacy Endpoints")
add_paragraph("Body weight and fasting glucose improvements were also noted for NXP-XR compared to Metformin hydrochloride.")
add_paragraph("")

add_paragraph("Safety Evaluation")
add_paragraph("Adverse Events")
add_paragraph("No serious adverse events were reported for Acme Pharma Inc. products.")
add_paragraph("Clinical Laboratory Evaluations")
add_paragraph("Routine lab tests showed no clinically significant abnormalities. The incidence of adverse events was similar across groups.")
add_paragraph("")

add_paragraph("Discussion and Conclusions")
add_paragraph("The drug Nexapril Extended Release is a safe and effective treatment for type-2 diabetes. The observed reduction in Hba1c is clinically meaningful.")
add_paragraph("The sponsor, ACME Pharmaceuticals, concludes that the risk-benefit profile is highly favorable.")

doc.save("/home/ga/Documents/clinical_study_report.odt")
PYEOF

chown ga:ga /home/ga/Documents/clinical_study_report.odt

echo "$(date +%s)" > /tmp/task_start_time.txt

launch_calligra_document "/home/ga/Documents/clinical_study_report.odt"

# Wait for Calligra to load and maximize the window
for i in {1..30}; do
    WID=$(get_calligra_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="