#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Adoption Home Study Task ==="

# Create directories
install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

# Clean up any existing state
kill_calligra_processes
rm -f /home/ga/Documents/raw_home_study.odt
rm -f /home/ga/Desktop/homestudy_guidelines.txt

# Create the unformatted Home Study document using odfpy
# All text is dumped as plain paragraphs with no structure or tables
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# Title
add_paragraph("CONFIDENTIAL: ADOPTION HOME STUDY REPORT")
add_paragraph("")

# Raw Demographics
add_paragraph("Applicant 1: Michael Sterling, DOB: 04/12/1984, Occupation: Civil Engineer. Applicant 2: Sarah Sterling, DOB: 08/25/1985, Occupation: Pediatric Nurse. Marriage Date: 06/15/2010.")
add_paragraph("")

# Section 1
add_paragraph("Introduction")
add_paragraph("This report summarizes the findings of the home study evaluation conducted for Michael and Sarah Sterling. The evaluation consisted of three joint interviews, two individual interviews, and a comprehensive home visit conducted over a period of six weeks. The purpose of this evaluation is to assess the applicants' suitability for the adoptive placement of a child.")
add_paragraph("")

# Section 2
add_paragraph("Motivation for Adoption")
add_paragraph("The applicants expressed a strong desire to expand their family. They have been married for fifteen years and after experiencing secondary infertility, they concluded that adoption was the right path for them.")
add_paragraph("We always knew we wanted to adopt, even before we got married. It has always been our dream to provide a loving home to a child in need, regardless of biology.")
add_paragraph("")

# Section 3
add_paragraph("Family Background")
add_paragraph("Applicant 1: Michael")
add_paragraph("Michael was raised in a suburban neighborhood in the Midwest. He describes his upbringing as stable and nurturing. His parents have been married for forty years and he maintains a close relationship with his two younger siblings.")
add_paragraph("My childhood was filled with outdoor activities and a strong emphasis on education and community service. I want to pass those same values on to our future child.")
add_paragraph("")
add_paragraph("Applicant 2: Sarah")
add_paragraph("Sarah grew up in a large extended family environment. Both of her parents were educators, which instilled in her a deep appreciation for learning and development. She is the eldest of four children.")
add_paragraph("Our parenting philosophy is based on mutual respect, open communication, and unconditional love. We believe in setting clear boundaries while encouraging a child's unique interests.")
add_paragraph("")

# Section 4
add_paragraph("Physical Environment")
add_paragraph("The applicants reside in a 3-bedroom, 2-bathroom single-family home in a quiet residential neighborhood. The home is well-maintained, free of hazards, and adequately child-proofed. The designated child's bedroom is on the same floor as the master suite and features ample natural light.")
add_paragraph("")

# Section 5
add_paragraph("Financial Status")
add_paragraph("The couple demonstrates exceptional financial stability. They possess a combined annual income that easily supports their lifestyle with sufficient surplus. They maintain comprehensive health insurance, life insurance policies, and have established a dedicated college savings fund.")
add_paragraph("")

# Section 6
add_paragraph("References")
add_paragraph("Three personal references and one professional reference were interviewed. All references spoke highly of the couple's moral character, stability, and emotional maturity. No concerns were raised regarding their capacity to parent.")
add_paragraph("")

# Section 7
add_paragraph("Recommendation and Summary")
add_paragraph("Based on the comprehensive evaluation, Michael and Sarah Sterling are highly recommended for the placement of a child. They possess the emotional maturity, financial resources, and loving environment necessary to foster a child's growth and development. They are approved for the adoption of one child between the ages of 0 and 5 years.")
add_paragraph("")

# Signature Block
add_paragraph("Sarah Jenkins, LCSW")
add_paragraph("License # 884729")
add_paragraph("Date: October 24, 2025")

doc.save("/home/ga/Documents/raw_home_study.odt")
PYEOF

chown ga:ga /home/ga/Documents/raw_home_study.odt

# Create the formatting guidelines document
cat > /home/ga/Desktop/homestudy_guidelines.txt << 'EOF'
ADOPTION HOME STUDY - FORMATTING GUIDELINES
For Submission to State Family Court

1. Title: The main report title ("CONFIDENTIAL: ADOPTION HOME STUDY REPORT") must be centered, bold, and at least 16pt font.

2. Demographics Table: Locate the raw paragraph containing the applicant names, DOBs, occupations, and marriage date. Convert this text into a 2-column, 4-row table summarizing the demographic data.

3. Main Sections: Format the 7 main section headings (Introduction, Motivation for Adoption, Family Background, Physical Environment, Financial Status, References, Recommendation and Summary) as Heading 1.

4. Subsections: Format the applicant-specific headings under Family Background ("Applicant 1: Michael" and "Applicant 2: Sarah") as Heading 2.

5. Blockquotes: The 3 direct quotes from the applicants must be formatted as blockquotes. To do this, increase the left margin of the paragraph (indentation) and italicize the text.

6. Pagination: Insert a page break immediately before the "Recommendation and Summary" section heading so it stands alone on its own page.

7. Sign-off: The social worker's signature block at the end (name, license, date) must be right-aligned (or centered on the right half of the page).
EOF

chown ga:ga /home/ga/Desktop/homestudy_guidelines.txt

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Launch Calligra Words with the target document
echo "Launching Calligra Words..."
launch_calligra_document "/home/ga/Documents/raw_home_study.odt"

# Wait for and configure window
sleep 3
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize window for best agent visibility
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot showing setup state
sleep 1
take_screenshot /tmp/task_initial.png ga

echo "=== Task Setup Complete ==="