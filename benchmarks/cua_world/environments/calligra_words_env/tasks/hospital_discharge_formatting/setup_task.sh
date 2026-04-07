#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Hospital Discharge Formatting Task ==="

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

kill_calligra_processes

rm -f /home/ga/Documents/discharge_summary_raw.odt
rm -f /home/ga/Desktop/hospital_style_guide.txt

# 1. Create the style guide
cat > /home/ga/Desktop/hospital_style_guide.txt << 'EOF'
HOSPITAL DISCHARGE SUMMARY - FORMATTING STYLE GUIDE

To ensure patient safety and readability, all discharge summaries must be formatted as follows:

1. TITLE: The top line ("HOSPITAL DISCHARGE SUMMARY") must be Centered, Bold, and at least 15pt font size.
2. DEMOGRAPHICS: The patient demographic information (Patient Name, MRN, Admission Date, Discharge Date, Attending Physician) must be converted into a 2-column table. Do not leave them as plain text lines.
3. SECTIONS: Apply the "Heading 1" style to the 5 main section headers (ADMISSION DIAGNOSES, DISCHARGE DIAGNOSES, HOSPITAL COURSE, DISCHARGE MEDICATIONS, DISCHARGE INSTRUCTIONS).
4. MEDICATIONS: The medications listed in the DISCHARGE MEDICATIONS section must be formatted as a bulleted list (one medication per bullet point).
5. CRITICAL WARNING: In the DISCHARGE INSTRUCTIONS section, the sentence starting with "Return to emergency room if..." must be emphasized using BOTH Bold and Underline formatting so it stands out to the patient.
EOF

chown ga:ga /home/ga/Desktop/hospital_style_guide.txt

# 2. Create the unformatted raw dictation draft using odfpy
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

add_paragraph("HOSPITAL DISCHARGE SUMMARY")
add_paragraph("")
add_paragraph("Patient Name: Robert Evans")
add_paragraph("MRN: 8849201")
add_paragraph("Admission Date: October 12, 2025")
add_paragraph("Discharge Date: October 16, 2025")
add_paragraph("Attending Physician: Dr. Sarah Jenkins")
add_paragraph("")
add_paragraph("ADMISSION DIAGNOSES")
add_paragraph("1. Acute decompensated heart failure.")
add_paragraph("2. Type 2 Diabetes Mellitus, uncontrolled.")
add_paragraph("3. Hypertension.")
add_paragraph("")
add_paragraph("DISCHARGE DIAGNOSES")
add_paragraph("1. Acute on chronic systolic heart failure, compensated.")
add_paragraph("2. Type 2 Diabetes Mellitus.")
add_paragraph("3. Essential hypertension.")
add_paragraph("")
add_paragraph("HOSPITAL COURSE")
add_paragraph("The patient is a 68-year-old male with a history of ischemic cardiomyopathy who presented to the emergency department with worsening shortness of breath, orthopnea, and lower extremity edema over the past 4 days. In the ED, he was hypoxic and required 2L of supplemental oxygen. Chest X-ray showed bilateral pleural effusions and pulmonary edema. He was admitted to the telemetry unit and started on intravenous Furosemide diuresis.")
add_paragraph("Over the first 48 hours, the patient had a net negative fluid balance of 4.5 liters and his respiratory status significantly improved. He was transitioned to room air. An echocardiogram showed a left ventricular ejection fraction of 35%, unchanged from prior. His diabetes was managed with sliding scale insulin and his home Metformin was resumed once his renal function stabilized.")
add_paragraph("By hospital day 4, the patient was back to his baseline weight and ambulating without dyspnea. He was transitioned to oral diuretics and deemed stable for discharge.")
add_paragraph("")
add_paragraph("DISCHARGE MEDICATIONS")
add_paragraph("Furosemide 40 mg PO daily.")
add_paragraph("Lisinopril 10 mg PO daily.")
add_paragraph("Metformin 1000 mg PO twice daily.")
add_paragraph("")
add_paragraph("DISCHARGE INSTRUCTIONS")
add_paragraph("Take your medications exactly as prescribed. Weigh yourself every morning after using the restroom and before eating. Record your weight in a log. Follow a low sodium diet (less than 2000 mg per day). Return to emergency room if experiencing severe shortness of breath, chest pain, or weight gain of more than 3 pounds in one day. Follow up with Dr. Jenkins in the cardiology clinic in 1 week.")

doc.save("/home/ga/Documents/discharge_summary_raw.odt")
PYEOF

chown ga:ga /home/ga/Documents/discharge_summary_raw.odt

# 3. Launch Calligra Words with the document
echo "Launching Calligra Words..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid calligrawords /home/ga/Documents/discharge_summary_raw.odt > /tmp/calligra_task.log 2>&1 < /dev/null &"

# Wait for window to appear
wait_for_window "Calligra Words\|discharge_summary_raw" 30

WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    echo "Found Calligra window: $WID"
    focus_window "$WID"
    # Maximize the window
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Record task start time
date +%s > /tmp/task_start_time.txt

# Capture initial screenshot
sleep 1
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="