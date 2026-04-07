#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Epidemiological Report Formatting Task ==="

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop
kill_calligra_processes
rm -f /home/ga/Documents/outbreak_report.odt
rm -f /home/ga/Desktop/bulletin_guidelines.txt

# ---------------------------------------------------------------------------
# Create the guidelines text file
# ---------------------------------------------------------------------------
cat << 'EOF' > /home/ga/Desktop/bulletin_guidelines.txt
STATE EPIDEMIOLOGICAL BULLETIN - SUBMISSION GUIDELINES

All outbreak investigation reports must strictly adhere to the following formatting standards before publication:

1. PAGE LAYOUT:
   The document must use a 2-column page layout to match our bulletin style.

2. HEADING STRUCTURE:
   The 5 main sections of the report must be formatted using the "Heading 1" style.

3. SCIENTIFIC NOMENCLATURE:
   Per taxonomic standards, all instances of the pathogen's scientific name (Listeria monocytogenes) must be italicized in the body text. Do not italicize the genus name when used alone (e.g., Listeria) unless referring to the specific species.

4. EPIDEMIOLOGICAL DATA:
   Raw comma-separated data under the table heading must be converted into a formal Table (6 columns by 6 rows). 
   The table's caption ("Table 1: Food-Specific Attack Rates for Implicated Items") must be formatted in Bold.

5. TYPOGRAPHY:
   All body paragraphs must have Justified alignment to ensure clean column edges.
EOF
chown ga:ga /home/ga/Desktop/bulletin_guidelines.txt

# ---------------------------------------------------------------------------
# Create the unformatted outbreak report document (all plain paragraphs)
# ---------------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# Title
add_paragraph("Multistate Outbreak of Listeriosis Linked to Deli Meats")
add_paragraph("Investigative Report - October 2025")
add_paragraph("")

# Section 1: Background
add_paragraph("Background")
add_paragraph(
    "On October 12, 2025, the State Department of Health was notified of a cluster "
    "of severe illnesses characterized by fever, muscle aches, and bacteremia. Initial "
    "blood cultures from three hospitalized patients confirmed infection with Listeria monocytogenes. "
    "Given the severity of the infections and the spatial clustering of cases, a rapid "
    "epidemiological response was initiated to identify the vehicle of infection and prevent further spread."
)
add_paragraph("")

# Section 2: Epidemiologic Investigation
add_paragraph("Epidemiologic Investigation")
add_paragraph(
    "A matched case-control study was conducted to identify the source of the outbreak. "
    "A case was defined as a state resident with a laboratory-confirmed Listeria monocytogenes "
    "infection with symptom onset between September 15 and October 20, 2025. Controls were "
    "matched by age group and neighborhood. Standardized food exposure questionnaires were "
    "administered to 18 cases and 36 controls. Analysis revealed a strong association between "
    "illness and the consumption of sliced deli meats purchased from a specific regional "
    "grocery chain (Chain A)."
)
add_paragraph("")
add_paragraph("Table 1: Food-Specific Attack Rates for Implicated Items")
add_paragraph("Item, Ill, Well, Total, Attack Rate (%), Relative Risk")
add_paragraph("Deli Turkey, 14, 2, 16, 87.5, 4.2")
add_paragraph("Roast Beef, 8, 5, 13, 61.5, 1.8")
add_paragraph("Ham, 4, 10, 14, 28.6, 0.9")
add_paragraph("Swiss Cheese, 12, 4, 16, 75.0, 3.1")
add_paragraph("Cheddar Cheese, 3, 11, 14, 21.4, 0.8")
add_paragraph("")

# Section 3: Laboratory and Environmental Investigation
add_paragraph("Laboratory and Environmental Investigation")
add_paragraph(
    "Environmental swabs were collected from the deli slicers, display cases, and preparation "
    "surfaces at three implicated locations of Chain A. Whole Genome Sequencing (WGS) was "
    "performed on clinical isolates and environmental samples. The WGS analysis demonstrated "
    "that the Listeria monocytogenes strains isolated from the patients were highly related "
    "(within 0-2 alleles) to the strains recovered from two deli slicers and a floor drain at "
    "the central processing facility."
)
add_paragraph("")

# Section 4: Public Health Response
add_paragraph("Public Health Response")
add_paragraph(
    "The implicated deli meats were recalled on October 25. The processing facility voluntarily "
    "suspended operations to undergo deep cleaning and sanitization. The Department of Health "
    "issued a public advisory urging consumers, particularly pregnant women, the elderly, and "
    "immunocompromised individuals, to discard any deli meats purchased from Chain A during "
    "the exposure window."
)
add_paragraph("")

# Section 5: Discussion
add_paragraph("Discussion")
add_paragraph(
    "This outbreak highlights the persistent challenge of controlling Listeria monocytogenes "
    "in ready-to-eat meat processing environments. The pathogen's ability to survive and multiply "
    "at refrigeration temperatures, coupled with its capacity to form persistent biofilms on "
    "stainless steel equipment, underscores the necessity of stringent sanitation protocols and "
    "routine environmental monitoring programs in retail delis."
)

doc.save("/home/ga/Documents/outbreak_report.odt")
PYEOF
chown ga:ga /home/ga/Documents/outbreak_report.odt

# ---------------------------------------------------------------------------
# Launch Calligra Words
# ---------------------------------------------------------------------------
echo "Launching Calligra Words..."
launch_calligra_document "/home/ga/Documents/outbreak_report.odt"

# Wait for Calligra to appear
if wait_for_window "Calligra Words\|outbreak_report" 30; then
    WID=$(get_calligra_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        sleep 1
    fi
else
    echo "Warning: Calligra Words window not found within timeout."
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Setup Complete ==="