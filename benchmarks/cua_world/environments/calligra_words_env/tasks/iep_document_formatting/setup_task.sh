#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up IEP Document Formatting Task ==="

# Timestamp for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure clean state
kill_calligra_processes

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

rm -f /home/ga/Documents/draft_iep_jordan.odt
rm -f /home/ga/Desktop/district_iep_format_guide.txt

# 1. Create the formatting specification guide on Desktop
cat << 'EOF' > /home/ga/Desktop/district_iep_format_guide.txt
DISTRICT IEP FORMATTING GUIDE

1. TITLE:
   - The main title ("INDIVIDUALIZED EDUCATION PROGRAM") must be bold, centered, and at least 16pt font.

2. DEMOGRAPHICS:
   - Convert the 4 demographic lines into a 2x2 table to save space.
   - Row 1: Student Name, Date of Birth
   - Row 2: Grade, Disability

3. SECTIONS:
   - Apply "Heading 1" style to all 5 main section headers: Present Levels of Academic Achievement, Annual Goals, Special Education Services, Accommodations, and Signatures.

4. BODY TEXT:
   - The narrative text under "Present Levels of Academic Achievement" must have justified alignment.

5. LISTS:
   - The 4 Annual Goals must be formatted as a Numbered List.
   - The 5 Accommodations must be formatted as a Bulleted List.

6. SERVICES:
   - Convert the comma-separated Special Education Services text into a 3x4 table.
   - The first row ("Service, Frequency, Duration, Location") must act as the table header and its text must be bolded.
EOF
chown ga:ga /home/ga/Desktop/district_iep_format_guide.txt

# 2. Create the unformatted raw IEP document using odfpy
cat << 'PYEOF' > /tmp/create_doc.py
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add(text=""):
    doc.text.addElement(P(text=text))

add("INDIVIDUALIZED EDUCATION PROGRAM")
add("Student Name: Jordan Smith")
add("Date of Birth: 2015-08-12")
add("Grade: 4th")
add("Disability: Specific Learning Disability")
add("")
add("Present Levels of Academic Achievement")
add("Jordan is a 4th-grade student who enjoys science and hands-on activities. In reading, Jordan currently reads at a mid-2nd-grade level and struggles with multisyllabic word decoding and reading comprehension. In math, Jordan performs near grade level in calculation but has difficulty with multi-step word problems due to reading barriers.")
add("")
add("Annual Goals")
add("Goal 1: By the next annual review, when given a 3rd-grade level text, Jordan will read 90 words correct per minute with 95% accuracy as measured by teacher records.")
add("Goal 2: By the next annual review, Jordan will correctly answer 4/5 literal comprehension questions about a 3rd-grade level text on 3 consecutive trials.")
add("Goal 3: By the next annual review, Jordan will successfully solve two-step math word problems with 80% accuracy in 3 out of 4 trials.")
add("Goal 4: By the next annual review, Jordan will independently use a graphic organizer to plan a 5-sentence paragraph on 4 out of 5 observed opportunities.")
add("")
add("Special Education Services")
add("Service, Frequency, Duration, Location")
add("Specialized Academic Instruction, Weekly, 120 minutes, Resource Room")
add("Speech and Language, Weekly, 30 minutes, Therapy Room")
add("")
add("Accommodations")
add("Text-to-speech software for lengthy reading assignments")
add("Extended time (1.5x) on written assessments")
add("Graphic organizers provided for writing tasks")
add("Check for understanding after multi-step verbal directions")
add("Use of a calculator for math problem-solving activities not assessing calculation")
add("")
add("Signatures")
add("Parent Signature: _______________________ Date: ___________")
add("Case Manager Signature: _______________________ Date: ___________")

doc.save("/home/ga/Documents/draft_iep_jordan.odt")
PYEOF

python3 /tmp/create_doc.py
chown ga:ga /home/ga/Documents/draft_iep_jordan.odt

# 3. Launch Calligra Words and open the document
launch_calligra_document "/home/ga/Documents/draft_iep_jordan.odt"

# Wait for window and maximize (CRITICAL for visual agent tasks)
wait_for_window "Calligra Words" 30 || true
wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$wid" || true
fi

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 4. Take initial screenshot evidence
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="