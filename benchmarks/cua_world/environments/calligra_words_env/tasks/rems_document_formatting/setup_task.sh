#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up REMS Document Formatting Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

kill_calligra_processes

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

rm -f /home/ga/Documents/mycophenolate_rems_draft.odt
rm -f /home/ga/Desktop/fda_rems_style_guide.txt

# Create the formatting spec file
cat > /home/ga/Desktop/fda_rems_style_guide.txt << 'EOF'
FDA REMS Formatting Style Guide
-------------------------------
1. Title: The document title ("Mycophenolate Shared System REMS") must be centered, bolded, and at least 16pt font.

2. Black Box Warning: The two paragraphs starting with "WARNING: EMBRYO-FETAL TOXICITY" and ending with "pregnancy prevention and planning." must be placed inside a 1x1 table (1 column, 1 row) to visually represent a Black Box Warning.

3. Headings:
   - Apply "Heading 1" style to the four main numbered sections (e.g., "1. Goals").
   - Apply "Heading 2" style to the three lettered subsections under REMS Elements (e.g., "A. Healthcare Providers").

4. Lists: The specific requirements for Healthcare Providers, Patients, and Pharmacies (the lines under their respective headings) must be formatted as proper bulleted lists.

5. Timetable: Under section "3. Timetable for Submission of Assessments", convert the assessment schedule ("1st Assessment: 18 Months", etc.) into a 2-column table. Column 1 should contain the Assessment Number, and Column 2 should contain the Timeframe.
EOF

chown ga:ga /home/ga/Desktop/fda_rems_style_guide.txt

# Create the unformatted document using odfpy
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

add_paragraph("Mycophenolate Shared System REMS")
add_paragraph("Initial Approval: September 2012")
add_paragraph("Most Recent Modification: October 2025")
add_paragraph("")
add_paragraph("WARNING: EMBRYO-FETAL TOXICITY")
add_paragraph("Use of mycophenolate during pregnancy is associated with increased risks of first trimester pregnancy loss and congenital malformations. Females of reproductive potential must be counseled regarding pregnancy prevention and planning.")
add_paragraph("")
add_paragraph("1. Goals")
add_paragraph("The goals of the Mycophenolate REMS are to mitigate the risk of embryofetal toxicity associated with mycophenolate by:")
add_paragraph("Educating healthcare providers and patients about the risks.")
add_paragraph("Ensuring females of reproductive potential are informed of the need for effective contraception.")
add_paragraph("")
add_paragraph("2. REMS Elements")
add_paragraph("")
add_paragraph("A. Healthcare Providers")
add_paragraph("To become certified to prescribe mycophenolate, healthcare providers must:")
add_paragraph("Must be certified in the Mycophenolate REMS.")
add_paragraph("Must counsel patients on the risk of embryo-fetal toxicity.")
add_paragraph("Must enroll female patients of reproductive potential.")
add_paragraph("")
add_paragraph("B. Patients")
add_paragraph("Patients who are prescribed mycophenolate must:")
add_paragraph("Understand the risks of birth defects and miscarriage.")
add_paragraph("Agree to use acceptable contraception during treatment.")
add_paragraph("")
add_paragraph("C. Pharmacies")
add_paragraph("Pharmacies that dispense mycophenolate must:")
add_paragraph("Verify the prescriber is certified.")
add_paragraph("Provide the Medication Guide to each patient.")
add_paragraph("")
add_paragraph("3. Timetable for Submission of Assessments")
add_paragraph("The assessment schedule is as follows:")
add_paragraph("1st Assessment: 18 Months")
add_paragraph("2nd Assessment: 3 Years")
add_paragraph("3rd Assessment: 7 Years")
add_paragraph("")
add_paragraph("4. REMS Materials")
add_paragraph("The following materials are part of the Mycophenolate REMS:")
add_paragraph("Prescriber Training Program")
add_paragraph("Patient-Prescriber Acknowledgment Form")

doc.save("/home/ga/Documents/mycophenolate_rems_draft.odt")
PYEOF

chown ga:ga /home/ga/Documents/mycophenolate_rems_draft.odt

# Launch Calligra Words with the document
launch_calligra_document "/home/ga/Documents/mycophenolate_rems_draft.odt"
wait_for_window "Calligra Words" 30

WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot for visual validation of state
sleep 2
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="