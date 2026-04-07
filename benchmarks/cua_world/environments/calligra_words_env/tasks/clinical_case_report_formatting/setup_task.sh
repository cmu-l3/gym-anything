#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Clinical Case Report Formatting Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

kill_calligra_processes

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

rm -f /home/ga/Documents/case_report.odt
rm -f /home/ga/Desktop/bmj_case_reports_guidelines.txt

# Create the BMJ formatting guidelines file
cat > /home/ga/Desktop/bmj_case_reports_guidelines.txt << 'EOF'
BMJ Case Reports - Author Formatting Guidelines:

Before submission, please ensure your manuscript adheres to the following formatting requirements:

1. Title Formatting: The main manuscript title must be bold and have a font size of at least 14pt.
2. Section Headings: Use the 'Heading 1' style for all main section titles (Abstract, Background, Case Presentation, Investigations, Differential Diagnosis, Treatment, Outcome and Follow-up, Discussion, Patient's Perspective, Learning Points, References).
3. Body Text: All body paragraphs must be justified (alignment) and use a font size of at least 11pt to ensure readability.
4. Tables: Do not submit tabular data as plain text. You must use the word processor's Table feature to properly format the Laboratory Values and Treatment Timeline data. The laboratory values table must contain at least 5 rows of data (including headers).
5. Learning Points: The key takeaways in the "Learning Points" section must be formatted as a proper bulleted or numbered list using the word processor's list feature.
6. Table of Contents: Insert a formal Table of Contents at the beginning of the document to aid reviewers in navigation.
EOF
chown ga:ga /home/ga/Desktop/bmj_case_reports_guidelines.txt

# Create the unformatted case report using odfpy
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# Title Page
add_paragraph("Euglycemic Diabetic Ketoacidosis Associated with SGLT2 Inhibitor Use in a Patient with Type 2 Diabetes: A Case Report")
add_paragraph("Dr. Sarah Jenkins, Dr. Robert Chen, Dr. Emily Stone")
add_paragraph("Department of Endocrinology, Metropolitan General Hospital")
add_paragraph("")

add_paragraph("Abstract")
add_paragraph("Background: Sodium-glucose cotransporter-2 (SGLT2) inhibitors are increasingly used for the management of type 2 diabetes. A rare but serious complication is euglycemic diabetic ketoacidosis (eDKA). Case Presentation: A 54-year-old male with type 2 diabetes presented with nausea, vomiting, and abdominal pain three weeks after starting empagliflozin. Investigations: Laboratory results revealed severe metabolic acidosis with elevated ketones, but normal blood glucose levels (135 mg/dL). Treatment: The patient was successfully managed with intravenous fluids, insulin infusion, and dextrose replacement. Outcome: The patient recovered fully and was transitioned to alternative antihyperglycemic therapy. Learning Points: Clinicians must maintain a high index of suspicion for eDKA in patients on SGLT2 inhibitors presenting with symptoms of ketoacidosis, even if blood glucose is normal.")
add_paragraph("")

add_paragraph("Background")
add_paragraph("Sodium-glucose cotransporter-2 (SGLT2) inhibitors represent a significant advancement in the management of type 2 diabetes mellitus, offering benefits beyond glycemic control, including cardiovascular and renal protection. However, post-marketing surveillance has identified a risk of euglycemic diabetic ketoacidosis (eDKA), defined as DKA with a blood glucose level less than 250 mg/dL. This atypical presentation can lead to delayed diagnosis and treatment. We report a classic case of SGLT2 inhibitor-induced eDKA to highlight the diagnostic challenges and management strategies.")
add_paragraph("")

add_paragraph("Case Presentation")
add_paragraph("A 54-year-old male with a 10-year history of type 2 diabetes presented to the emergency department with a two-day history of progressive nausea, vomiting, generalized abdominal pain, and profound fatigue. His past medical history was significant for hypertension and hyperlipidemia. His outpatient medications included metformin 1000 mg twice daily and empagliflozin 25 mg daily, which had been initiated three weeks prior to presentation. On examination, he appeared dehydrated and tachypneic. His vital signs showed a heart rate of 115 bpm, blood pressure of 105/65 mmHg, respiratory rate of 24 breaths/min, and oxygen saturation of 98% on room air. Abdominal examination revealed diffuse tenderness without rebound or guarding.")
add_paragraph("")

add_paragraph("Investigations")
add_paragraph("Initial laboratory evaluation revealed a severe high anion gap metabolic acidosis. Strikingly, his blood glucose was within the normal range at 135 mg/dL. Urinalysis was strongly positive for ketones (4+) and glucose (4+). Serum beta-hydroxybutyrate was markedly elevated. Below are the key laboratory trends during his admission:")
add_paragraph("")
add_paragraph("Parameter | Admission | 24 Hours | 48 Hours | Reference Range")
add_paragraph("Blood Glucose (mg/dL) | 135 | 142 | 110 | 70-99")
add_paragraph("Serum pH | 7.15 | 7.32 | 7.41 | 7.35-7.45")
add_paragraph("Bicarbonate (mmol/L) | 8 | 16 | 24 | 22-29")
add_paragraph("Anion Gap (mmol/L) | 26 | 14 | 10 | 8-12")
add_paragraph("Beta-hydroxybutyrate (mmol/L) | 8.5 | 3.2 | 0.4 | 0.02-0.27")
add_paragraph("Potassium (mmol/L) | 5.2 | 4.1 | 4.0 | 3.5-5.1")
add_paragraph("Sodium (mmol/L) | 132 | 136 | 138 | 135-145")
add_paragraph("BUN (mg/dL) | 35 | 22 | 15 | 7-20")
add_paragraph("Creatinine (mg/dL) | 1.8 | 1.1 | 0.9 | 0.7-1.3")
add_paragraph("")

add_paragraph("Differential Diagnosis")
add_paragraph("The differential diagnosis for a high anion gap metabolic acidosis includes lactic acidosis, ketoacidosis (diabetic, alcoholic, starvation), and toxic alcohol ingestion (methanol, ethylene glycol). The patient denied alcohol use or toxic ingestions. Lactate levels were normal (1.2 mmol/L). The presence of heavy ketonuria and markedly elevated serum beta-hydroxybutyrate confirmed the diagnosis of ketoacidosis. Given the normal blood glucose levels and recent initiation of empagliflozin, a diagnosis of SGLT2 inhibitor-induced eDKA was established.")
add_paragraph("")

add_paragraph("Treatment")
add_paragraph("The patient was admitted to the medical intensive care unit. Empagliflozin was immediately discontinued. The following timeline details the clinical interventions:")
add_paragraph("")
add_paragraph("Time | Intervention | Details")
add_paragraph("Hour 0 | Intravenous Fluids | Started 1 L/hr of 0.9% Normal Saline")
add_paragraph("Hour 2 | Insulin Infusion | Initiated continuous regular insulin at 0.1 units/kg/hr")
add_paragraph("Hour 2 | Dextrose Administration | Started 5% Dextrose in 0.45% Normal Saline due to euglycemia")
add_paragraph("Hour 6 | Electrolyte Repletion | Added potassium chloride 20 mEq/L to IV fluids")
add_paragraph("Hour 12 | Fluid Adjustment | Decreased fluid rate to 250 mL/hr based on improved hemodynamics")
add_paragraph("Hour 24 | Insulin Adjustment | Decreased insulin drip rate as anion gap improved")
add_paragraph("Hour 36 | Transition | Discontinued IV insulin, administered subcutaneous glargine")
add_paragraph("Hour 48 | Discharge | Patient stabilized, transitioned to oral diet and metformin/DPP-4 inhibitor")
add_paragraph("")

add_paragraph("Outcome and Follow-up")
add_paragraph("The patient's acidosis resolved completely within 36 hours. He was transferred to the general medical ward and subsequently discharged on hospital day 4. His empagliflozin was permanently discontinued, and sitagliptin was added to his metformin regimen. At his 3-month follow-up appointment, he was asymptomatic, and his HbA1c had improved to 7.2%. Renal function remained stable.")
add_paragraph("")

add_paragraph("Discussion")
add_paragraph("Euglycemic DKA is a well-documented but infrequent complication of SGLT2 inhibitors. The mechanism involves glucosuria-induced carbohydrate deficit, leading to decreased insulin secretion and increased glucagon release. This hormonal imbalance shifts energy metabolism toward lipid oxidation and ketogenesis. SGLT2 inhibitors may also stimulate glucagon secretion directly from pancreatic alpha cells and reduce ketone clearance by the kidneys. This case emphasizes that the absence of hyperglycemia does not preclude the diagnosis of DKA. Delayed recognition can lead to severe metabolic decompensation.")
add_paragraph("")

add_paragraph("Patient's Perspective")
add_paragraph("I felt incredibly weak and sick, but because my home blood sugar readings were normal, I thought it was just a stomach bug. I had no idea that a diabetes medication could cause such a severe problem while my blood sugars looked perfect. I'm grateful the doctors figured it out quickly.")
add_paragraph("")

add_paragraph("Learning Points")
add_paragraph("1. Clinicians must maintain a high index of suspicion for eDKA in patients taking SGLT2 inhibitors who present with malaise, nausea, or abdominal pain.")
add_paragraph("2. Normal blood glucose levels do not rule out diabetic ketoacidosis in this patient population.")
add_paragraph("3. Treatment of eDKA requires simultaneous administration of intravenous insulin to halt ketogenesis and dextrose-containing fluids to prevent hypoglycemia.")
add_paragraph("4. Patients initiating SGLT2 inhibitors should be routinely counseled on the signs and symptoms of ketoacidosis and advised to seek immediate medical attention if they occur.")
add_paragraph("")

add_paragraph("References")
add_paragraph("1. Peters AL, Buschur EO, Buse JB, et al. Euglycemic Diabetic Ketoacidosis: A Potential Complication of Treatment With Sodium-Glucose Cotransporter 2 Inhibition. Diabetes Care. 2015;38(9):1687-1693.")
add_paragraph("2. Rosenstock J, Ferrannini E. Euglycemic Diabetic Ketoacidosis: A Predictable, Detectable, and Preventable Safety Concern With SGLT2 Inhibitors. Diabetes Care. 2015;38(9):1638-1642.")
add_paragraph("3. Food and Drug Administration. FDA Drug Safety Communication: FDA warns that SGLT2 inhibitors for diabetes may result in a serious condition of too much acid in the blood. 2015.")
add_paragraph("4. Goldenberg RM, Berard LD, Cheng AYY, et al. SGLT2 Inhibitor-associated Diabetic Ketoacidosis: Clinical Review and Recommendations for Prevention and Diagnosis. Clin Ther. 2016;38(12):2654-2664.")

doc.save("/home/ga/Documents/case_report.odt")
PYEOF

chown ga:ga /home/ga/Documents/case_report.odt

# Launch Calligra Words with the document
launch_calligra_document "/home/ga/Documents/case_report.odt"
sleep 5

wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_initial.png ga

echo "=== Task Setup Complete ==="