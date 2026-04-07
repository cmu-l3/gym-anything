#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Regulatory Compliance Report Task ==="

kill_calligra_processes

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

rm -f /home/ga/Documents/phase1_esa_report.odt
rm -f /home/ga/Desktop/esa_formatting_spec.txt

# ------------------------------------------------------------------
# Create the unformatted Phase I ESA report using odfpy
# ALL content is plain P elements — no heading styles, no bold, etc.
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()


def add_paragraph(text=""):
    doc.text.addElement(P(text=text))


# ── Title page elements (plain paragraphs, no styles) ──
add_paragraph("Phase I Environmental Site Assessment")
add_paragraph("Riverside Industrial Complex")
add_paragraph("4500 Industrial Boulevard, Riverside, CA 92501")
add_paragraph("")
add_paragraph("Prepared for: Consolidated Development Group, LLC")
add_paragraph("Prepared by: EnviroTech Solutions, Inc.")
add_paragraph("Date: November 15, 2025")
add_paragraph("Project Number: ES-2025-1847")
add_paragraph("")

# ── Section 1: Executive Summary ──
add_paragraph("Executive Summary")
add_paragraph(
    "EnviroTech Solutions was retained by Consolidated Development Group, LLC "
    "to conduct a Phase I Environmental Site Assessment (ESA) of the former "
    "Riverside Industrial Complex located at 4500 Industrial Boulevard, "
    "Riverside, California 92501. This assessment was performed in conformance "
    "with the scope and limitations of ASTM E1527-21, Standard Practice for "
    "Environmental Site Assessments: Phase I Environmental Site Assessment Process."
)
add_paragraph(
    "The assessment identified three recognized environmental conditions (RECs) "
    "on the subject property. Evidence of petroleum hydrocarbons was detected in "
    "soil samples near the former fueling station on the eastern portion of the "
    "site. Two underground storage tanks (USTs) were identified beneath the "
    "northern loading dock area that do not appear in closure records maintained "
    "by the Regional Water Quality Control Board. Additionally, elevated levels "
    "of chlorinated solvents were detected in groundwater monitoring wells "
    "downgradient of the former degreasing operations building."
)
add_paragraph("")

# ── Section 2: Introduction ──
add_paragraph("Introduction")

add_paragraph("Purpose and Scope")
add_paragraph(
    "The purpose of this Phase I ESA is to identify recognized environmental "
    "conditions (RECs), controlled recognized environmental conditions (CRECs), "
    "and historical recognized environmental conditions (HRECs) in connection "
    "with the subject property, as defined by ASTM E1527-21. This assessment "
    "was conducted to support the due diligence requirements of Consolidated "
    "Development Group in connection with the proposed acquisition and "
    "redevelopment of the property."
)
add_paragraph(
    "The scope of services included a review of reasonably ascertainable "
    "environmental records, historical land use documentation, aerial "
    "photographs, topographic maps, fire insurance maps, and regulatory "
    "agency databases. A site reconnaissance visit was conducted, and "
    "interviews were performed with current and past property owners, "
    "operators, occupants, and local government officials."
)
add_paragraph("")

# ── Section 3: Site Description ──
add_paragraph("Site Description")

add_paragraph("Site Location and Legal Description")
add_paragraph(
    "The subject property is located at 4500 Industrial Boulevard in the City "
    "of Riverside, Riverside County, California 92501. The property is situated "
    "in the northwest quarter of Section 14, Township 3 South, Range 5 West, "
    "San Bernardino Base and Meridian. The property encompasses approximately "
    "12.5 acres and is identified by Assessor Parcel Numbers 245-180-001 "
    "through 245-180-008."
)

add_paragraph("Current Use of the Property")
add_paragraph(
    "The subject property is currently vacant and secured by chain-link fencing. "
    "The site contains four industrial buildings totaling approximately 85,000 "
    "square feet, a paved parking area, concrete loading docks, and remnants "
    "of above-ground process piping. The buildings were most recently occupied "
    "by Riverside Metal Fabricators, Inc. until operations ceased in March 2023. "
    "Prior to that, the property was used for various manufacturing operations "
    "dating back to 1958."
)
add_paragraph("")

# ── Section 4: Records Review ──
add_paragraph("Records Review")

add_paragraph("Environmental Database Search")
add_paragraph(
    "A search of environmental databases was conducted by Environmental Data "
    "Resources, Inc. (EDR) on September 28, 2025. The database search covered "
    "the subject property and surrounding area within the ASTM-specified search "
    "distances. The search included federal, state, and local environmental "
    "databases including CERCLIS, RCRA, NPL, state equivalent programs, "
    "leaking underground storage tank (LUST) databases, and registered UST "
    "databases."
)
add_paragraph(
    "The subject property was identified on the following databases: the "
    "California LUST database for a reported diesel fuel release in 1997, "
    "the registered UST database for three 10,000-gallon underground storage "
    "tanks installed in 1972, and the RCRA Small Quantity Generator database "
    "for hazardous waste generation associated with metal finishing operations."
)

add_paragraph("Historical Land Use Records")
add_paragraph(
    "Historical aerial photographs from 1952, 1965, 1978, 1990, 2005, and 2020 "
    "were reviewed. Sanborn fire insurance maps from 1955, 1968, and 1985 were "
    "also reviewed. These records indicate the property was agricultural land "
    "until approximately 1956 when the first industrial structures were "
    "constructed. The site has been continuously used for industrial and "
    "manufacturing purposes since that time."
)
add_paragraph("")

# ── Section 5: Site Reconnaissance ──
add_paragraph("Site Reconnaissance")

add_paragraph("Interior Observations")
add_paragraph(
    "The site reconnaissance was conducted on October 15, 2025 by Mr. David "
    "Chen, P.E., Senior Environmental Engineer with EnviroTech Solutions. "
    "Interior observations of the four industrial buildings revealed evidence "
    "of former chemical storage areas in Building 2, including stained concrete "
    "flooring and residual chemical odors. Floor drains were observed in "
    "Buildings 1, 2, and 3, with discharge points that could not be confirmed "
    "to connect to the municipal sanitary sewer system."
)

add_paragraph("Exterior Observations")
add_paragraph(
    "Exterior observations identified stressed vegetation along the northern "
    "property boundary adjacent to the former chemical loading area. Soil "
    "staining was observed near the eastern fueling island where three UST "
    "fill ports are visible at ground surface. Two monitoring wells were "
    "identified on the southern portion of the property; however, well "
    "completion records could not be located during the assessment."
)
add_paragraph("")

# ── Section 6: Interviews ──
add_paragraph("Interviews")
add_paragraph(
    "Interviews were conducted with Mr. Robert Hayes, the property owner since "
    "2010, and Ms. Linda Martinez, former plant manager for Riverside Metal "
    "Fabricators from 2015 to 2023. Mr. Hayes indicated he was unaware of any "
    "environmental releases on the property. Ms. Martinez reported that "
    "trichloroethylene (TCE) was used as a degreasing solvent in Building 2 "
    "until 2019 and that waste solvents were stored in 55-gallon drums on a "
    "concrete pad behind Building 2 prior to quarterly hazardous waste pickups."
)
add_paragraph(
    "Representatives of the Riverside County Department of Environmental Health "
    "and the Santa Ana Regional Water Quality Control Board were contacted. "
    "County records confirmed the 1997 diesel fuel release and indicated that "
    "the case was closed in 2003 following remediation. The Regional Board "
    "confirmed that the property is not currently under any cleanup orders or "
    "enforcement actions, but noted that historical groundwater monitoring data "
    "from the late 1990s showed detectable concentrations of volatile organic "
    "compounds in shallow groundwater beneath the site."
)
add_paragraph("")

# ── Section 7: Evaluation ──
add_paragraph("Evaluation")

add_paragraph("Data Gaps")
add_paragraph(
    "The following data gaps were identified during this assessment: (1) UST "
    "closure documentation could not be located for two of the three registered "
    "underground storage tanks; (2) the discharge points for interior floor "
    "drains in Buildings 1, 2, and 3 could not be confirmed; (3) groundwater "
    "monitoring data more recent than 2003 was not available; and (4) complete "
    "operational records for the period 1958 to 1985 were not obtainable. These "
    "data gaps do not significantly affect the ability to identify recognized "
    "environmental conditions but should be addressed in any subsequent Phase II "
    "investigation."
)

add_paragraph("Recognized Environmental Conditions")
add_paragraph(
    "Based on the findings of this Phase I ESA, the following recognized "
    "environmental conditions have been identified: REC-1: Evidence of petroleum "
    "hydrocarbon contamination in soil near the former fueling station on the "
    "eastern portion of the property, associated with the documented 1997 diesel "
    "release and the presence of USTs with incomplete closure records. REC-2: "
    "Two underground storage tanks beneath the northern loading dock that lack "
    "documented closure records and may still contain product or residual "
    "contamination. REC-3: Historical use of chlorinated solvents, specifically "
    "trichloroethylene, in Building 2 degreasing operations with potential for "
    "soil and groundwater impacts, supported by historical groundwater "
    "monitoring data showing VOC detections."
)
add_paragraph("")

# ── Section 8: Conclusions and Recommendations ──
add_paragraph("Conclusions and Recommendations")
add_paragraph(
    "Based on the findings of this Phase I ESA, three recognized environmental "
    "conditions were identified at the subject property. EnviroTech Solutions "
    "recommends that a Phase II Environmental Site Assessment be conducted to "
    "further evaluate the nature and extent of potential contamination associated "
    "with the identified RECs. Specifically, the Phase II investigation should "
    "include soil borings and groundwater sampling in the vicinity of the former "
    "fueling station, the northern loading dock UST area, and the Building 2 "
    "degreasing operations area."
)
add_paragraph(
    "Additionally, a geophysical survey should be conducted to confirm the "
    "location and status of the two underground storage tanks that lack closure "
    "documentation. An assessment of the interior floor drain systems should "
    "also be performed to determine discharge points and evaluate potential "
    "subsurface releases from these conveyances."
)
add_paragraph("")

# ── Table as plain text (no ODF table element) ──
add_paragraph("Table 1: Environmental Database Summary")
add_paragraph("Database | Search Distance | Findings")
add_paragraph("CERCLIS | 0.5 miles | No listings identified")
add_paragraph("RCRA-SQG | 0.25 miles | Subject property listed as SQG")
add_paragraph("UST | 0.25 miles | Three USTs registered at subject property")
add_paragraph("LUST | 0.5 miles | Diesel release reported 1997, case closed 2003")
add_paragraph("NPL | 1.0 mile | No listings identified")
add_paragraph("State Spills | 0.5 miles | Two reported releases within search radius")
add_paragraph("")

# ── Appendix reference ──
add_paragraph("Appendices")
add_paragraph("Appendix A: Site Vicinity Map and Site Plan")
add_paragraph("Appendix B: Environmental Database Report")
add_paragraph("Appendix C: Historical Aerial Photographs")
add_paragraph("Appendix D: Regulatory Agency Correspondence")
add_paragraph("Appendix E: Qualifications of Environmental Professional")

doc.save("/home/ga/Documents/phase1_esa_report.odt", False)
print("Created phase1_esa_report.odt with all plain paragraphs (no formatting)")
PYEOF

# ------------------------------------------------------------------
# Create the formatting specification file
# ------------------------------------------------------------------
cat > /home/ga/Desktop/esa_formatting_spec.txt << 'SPECEOF'
ASTM E1527-21 COMPLIANT FORMATTING SPECIFICATION
Phase I Environmental Site Assessment Reports

===============================================================

1. PAGE LAYOUT
   - Paper size: Letter (8.5 x 11 inches)
   - Margins: 1 inch on all sides (top, bottom, left, right)

2. TITLE PAGE
   - Report title: Centered, Bold, 16pt or larger font
   - Project name: Centered, Bold, 14pt
   - All other title page elements: Centered, 12pt

3. HEADING STYLES
   - Main section headings (e.g., Executive Summary, Introduction, etc.):
     Heading 1 style, Bold, 14pt, left-aligned
   - Subsection headings:
     Heading 2 style, Bold, 12pt, left-aligned

4. BODY TEXT
   - Font: Times New Roman, 12pt
   - Alignment: Justified
   - Line spacing: 1.15 or greater

5. TABLE OF CONTENTS
   - Insert a Table of Contents after the title page
   - TOC should list all Heading 1 and Heading 2 entries

6. TABLES
   - Table header rows: Bold text
   - All tables must have visible borders

7. PAGE NUMBERING
   - Page numbers in footer, centered
   - Title page should not have a page number

8. HEADER
   - Right-aligned header on all pages (except title page):
     "Phase I ESA - Riverside Industrial Complex"

===============================================================
END OF SPECIFICATION
SPECEOF

# ------------------------------------------------------------------
# Set ownership
# ------------------------------------------------------------------
chown ga:ga /home/ga/Documents/phase1_esa_report.odt
chmod 0664 /home/ga/Documents/phase1_esa_report.odt
chown ga:ga /home/ga/Desktop/esa_formatting_spec.txt
chmod 0644 /home/ga/Desktop/esa_formatting_spec.txt

# ------------------------------------------------------------------
# Launch Calligra Words with the report
# ------------------------------------------------------------------
echo "Launching Calligra Words..."
launch_calligra_document "/home/ga/Documents/phase1_esa_report.odt" "/tmp/calligra_words_task.log"

if ! wait_for_process "/usr/bin/calligrawords" 20; then
    wait_for_process "calligrawords" 15 || true
fi

if ! wait_for_window "Calligra Words\\|phase1_esa_report" 60; then
    echo "ERROR: Calligra Words window did not appear"
    cat /tmp/calligra_words_task.log || true
fi

wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid" || true
    safe_xdotool ga :1 key Escape || true
    sleep 0.5
    safe_xdotool ga :1 key ctrl+Home || true
fi

take_screenshot /tmp/calligra_regulatory_compliance_setup.png

echo "=== Regulatory Compliance Report Task Setup Complete ==="
