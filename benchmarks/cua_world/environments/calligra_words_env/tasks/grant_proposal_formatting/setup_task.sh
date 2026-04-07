#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Grant Proposal Formatting Task ==="

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop
kill_calligra_processes
rm -f /home/ga/Documents/nsf_proposal.odt

# ---------------------------------------------------------------------------
# Create the unformatted NSF proposal document (all plain paragraphs, no styles)
# ---------------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()


def add_paragraph(text=""):
    doc.text.addElement(P(text=text))


# ── Cover Page ──────────────────────────────────────────────────────────────
add_paragraph("Cover Page")
add_paragraph("")
add_paragraph(
    "Biochar-Amended Bioretention Systems for Enhanced Stormwater "
    "Treatment in Urban Watersheds"
)
add_paragraph("Principal Investigator: Dr. Elena Vasquez")
add_paragraph("Department of Environmental Engineering")
add_paragraph("Pacific Northwest University")
add_paragraph("NSF Program: Environmental Engineering (CBET-1440)")
add_paragraph("Requested Amount: $499,872")
add_paragraph("Duration: 36 months")
add_paragraph("Date: January 15, 2026")
add_paragraph("")

# ── Project Summary ─────────────────────────────────────────────────────────
add_paragraph("Project Summary")
add_paragraph("")
add_paragraph("Overview")
add_paragraph(
    "Urban stormwater runoff represents one of the most significant "
    "non-point source pollution challenges facing municipalities across "
    "the United States. As impervious surfaces expand with urbanization, "
    "the volume and pollutant loading of stormwater discharges continue "
    "to increase, degrading receiving water bodies and threatening aquatic "
    "ecosystems. This proposal presents a comprehensive investigation into "
    "the use of biochar-amended bioretention systems as a novel approach "
    "to enhanced stormwater treatment in urban watersheds. Biochar, a "
    "carbon-rich material produced through the pyrolysis of organic "
    "biomass, has demonstrated exceptional capacity for adsorbing heavy "
    "metals, polycyclic aromatic hydrocarbons (PAHs), and emerging "
    "contaminants from aqueous solutions. By integrating biochar into "
    "conventional bioretention filter media, we hypothesize that "
    "pollutant removal efficiencies can be increased by 40-60% compared "
    "to standard designs while maintaining adequate hydraulic performance."
)
add_paragraph("")
add_paragraph("Intellectual Merit")
add_paragraph(
    "The intellectual merit of this proposal lies in advancing fundamental "
    "understanding of contaminant transport mechanisms through "
    "biochar-amended filter media under dynamic hydrologic conditions. "
    "Current bioretention design standards do not account for the "
    "synergistic effects of biochar amendment on hydraulic conductivity, "
    "cation exchange capacity, and microbial community development. This "
    "research will fill critical knowledge gaps by quantifying the "
    "relationships between biochar properties (surface area, pore size "
    "distribution, surface functional groups) and pollutant removal "
    "performance across a range of storm intensities and antecedent "
    "moisture conditions. The development of a validated computational "
    "model linking biochar characteristics to treatment performance will "
    "provide a predictive framework that advances the science of "
    "green infrastructure design."
)
add_paragraph("")
add_paragraph("Broader Impacts")
add_paragraph(
    "This research will directly impact urban water quality management "
    "practices by developing evidence-based design guidelines for "
    "biochar-amended bioretention systems. The project integrates "
    "research with education through the training of two PhD students "
    "and four undergraduate researchers from underrepresented groups in "
    "STEM. A partnership with the City of Portland Bureau of Environmental "
    "Services will facilitate technology transfer and real-world "
    "implementation. Educational outreach includes development of a "
    "hands-on stormwater treatment module for K-12 students and a "
    "professional short course for practicing engineers. All data and "
    "models will be made publicly available through the CUAHSI "
    "HydroShare platform."
)
add_paragraph("")

# ── Project Description ─────────────────────────────────────────────────────
add_paragraph("Project Description")
add_paragraph("")

# Introduction and Motivation
add_paragraph("Introduction and Motivation")
add_paragraph(
    "Urban stormwater management has emerged as one of the most pressing "
    "environmental challenges of the 21st century. The Environmental "
    "Protection Agency estimates that stormwater runoff from developed "
    "areas impairs more than 80,000 miles of rivers and streams and "
    "contributes to beach closures, shellfish bed closures, and drinking "
    "water supply contamination nationwide. Traditional gray "
    "infrastructure approaches, such as detention basins and storm "
    "sewers, are increasingly recognized as insufficient for addressing "
    "the complex water quality challenges posed by urban runoff."
)
add_paragraph(
    "Green infrastructure practices, particularly bioretention systems "
    "(also known as rain gardens or biofilters), have gained widespread "
    "adoption as a sustainable alternative for managing stormwater at "
    "the source. Bioretention systems treat stormwater through a "
    "combination of physical filtration, chemical sorption, and "
    "biological uptake as water percolates through an engineered soil "
    "media. However, conventional bioretention designs exhibit variable "
    "and sometimes inadequate removal of dissolved pollutants, "
    "particularly dissolved metals, nutrients, and organic micropollutants."
)
add_paragraph(
    "This proposal addresses the critical need for improved bioretention "
    "performance by investigating the incorporation of biochar as a soil "
    "amendment. Biochar is a carbon-rich material produced through "
    "pyrolysis of organic feedstocks such as wood waste, agricultural "
    "residues, and biosolids. The unique physicochemical properties of "
    "biochar, including high specific surface area, abundant surface "
    "functional groups, and excellent cation exchange capacity, make it "
    "an ideal candidate for enhancing contaminant removal in "
    "bioretention systems."
)
add_paragraph("")

# Background and Related Work
add_paragraph("Background and Related Work")
add_paragraph(
    "Biochar has been extensively studied in agricultural applications "
    "as a soil amendment to improve soil fertility, water retention, and "
    "carbon sequestration. Lehmann and Joseph (2015) provided a "
    "comprehensive review of biochar properties and applications, "
    "documenting surface areas ranging from 1 to 800 m2/g depending on "
    "feedstock and pyrolysis conditions. Ahmad et al. (2014) reviewed "
    "the mechanisms of contaminant interaction with biochar, identifying "
    "electrostatic attraction, ion exchange, precipitation, and "
    "complexation as primary removal pathways for heavy metals."
)
add_paragraph(
    "The application of biochar to stormwater treatment is a relatively "
    "new area of investigation. Reddy et al. (2014) conducted batch "
    "sorption experiments demonstrating that biochar produced from "
    "switchgrass at 700 degrees Celsius removed over 95% of dissolved "
    "copper, zinc, and cadmium from synthetic stormwater. Ulrich et al. "
    "(2015) reported similar findings for phosphorus removal using "
    "iron-modified biochar. However, these studies were limited to "
    "controlled laboratory conditions and did not address the dynamic "
    "flow conditions encountered in field-scale bioretention systems."
)
add_paragraph(
    "Field-scale investigations of biochar-amended bioretention remain "
    "scarce. A notable study by Tian et al. (2019) monitored a "
    "biochar-amended bioretention cell over 18 months in North Carolina, "
    "reporting improved removal of total suspended solids and zinc "
    "compared to a conventional control cell. However, their study did "
    "not characterize changes in biochar properties over time or examine "
    "the impact on microbial community composition. The proposed research "
    "will address these gaps through a comprehensive, multi-scale "
    "investigation spanning laboratory experiments, field monitoring, "
    "and computational modeling."
)
add_paragraph("")

# Research Plan
add_paragraph("Research Plan")
add_paragraph(
    "The proposed research will employ a mixed-methods approach combining "
    "laboratory column experiments, field-scale bioretention cell "
    "monitoring, and computational modeling. The work is organized into "
    "three integrated tasks spanning the 36-month project duration."
)
add_paragraph(
    "Task 1: Laboratory Column Experiments (Months 1-18). We will "
    "construct a series of 12 laboratory-scale bioretention columns "
    "incorporating biochar produced from three feedstocks (Douglas fir "
    "wood chips, wheat straw, and wastewater biosolids) at two pyrolysis "
    "temperatures (450 and 700 degrees Celsius). Columns will be "
    "subjected to simulated storm events using synthetic stormwater "
    "spiked with target contaminants including copper, zinc, lead, "
    "phosphorus, nitrogen, and three polycyclic aromatic hydrocarbons "
    "(naphthalene, phenanthrene, and pyrene). Effluent samples will be "
    "analyzed using ICP-MS for metals and GC-MS for organic compounds. "
    "Hydraulic conductivity will be monitored continuously using "
    "differential pressure transducers."
)
add_paragraph(
    "Task 2: Field-Scale Deployment (Months 12-30). In partnership with "
    "the City of Portland, we will retrofit two existing bioretention "
    "cells in the Johnson Creek watershed with biochar-amended filter "
    "media. The optimal biochar type and amendment rate will be selected "
    "based on Task 1 results. Each cell will be instrumented with "
    "automated samplers, flow meters, soil moisture sensors, and "
    "temperature probes. A paired conventional bioretention cell will "
    "serve as a control. Monitoring will capture at least 30 storm "
    "events spanning wet and dry seasons."
)
add_paragraph(
    "Task 3: Computational Modeling (Months 6-36). We will develop a "
    "process-based numerical model using HYDRUS-2D coupled with "
    "PHREEQC to simulate water flow, solute transport, and "
    "geochemical reactions in biochar-amended bioretention systems. "
    "The model will be calibrated and validated against laboratory "
    "column data (Task 1) and field monitoring data (Task 2). "
    "Sensitivity analyses will identify the most critical biochar "
    "parameters influencing treatment performance, providing guidance "
    "for optimizing biochar selection and amendment rates in practice."
)
add_paragraph("")

# Expected Outcomes
add_paragraph("Expected Outcomes")
add_paragraph(
    "This research is expected to yield several significant outcomes. "
    "First, we will establish quantitative relationships between "
    "biochar properties and pollutant removal performance under "
    "realistic hydrologic conditions. Second, we will generate the "
    "first long-term field dataset on biochar-amended bioretention "
    "performance in the Pacific Northwest climate, including assessment "
    "of biochar aging effects. Third, we will produce a validated "
    "computational model capable of predicting treatment performance "
    "for arbitrary biochar-media combinations and climate scenarios."
)
add_paragraph(
    "These outcomes will directly inform the development of design "
    "guidelines for biochar-amended bioretention systems. We anticipate "
    "that the results will be adopted by municipalities and stormwater "
    "management agencies through our partnership with Portland and "
    "dissemination via the Water Environment Federation and American "
    "Society of Civil Engineers conferences and publications."
)
add_paragraph("")

# Timeline and Milestones
add_paragraph("Timeline and Milestones")
add_paragraph(
    "Year 1 (Months 1-12): Complete construction and initial operation "
    "of laboratory columns; begin biochar characterization; develop "
    "preliminary computational model framework; initiate field site "
    "design and permitting. Year 2 (Months 13-24): Complete laboratory "
    "column experiments; install field bioretention cells; begin field "
    "monitoring; calibrate model against laboratory data; submit first "
    "journal manuscript. Year 3 (Months 25-36): Continue field "
    "monitoring through second wet season; validate model against field "
    "data; develop design guidelines; submit two additional manuscripts; "
    "deliver final report and design tool to partner agencies."
)
add_paragraph("")

# ── References Cited ─────────────────────────────────────────────────────────
add_paragraph("References Cited")
add_paragraph("")
add_paragraph(
    "[1] Davis, A.P., et al. (2009). Bioretention technology: Overview "
    "of current practice and future needs. Journal of Environmental "
    "Engineering, 135(3), 109-117."
)
add_paragraph(
    "[2] Lehmann, J. and Joseph, S. (2015). Biochar for Environmental "
    "Management: Science, Technology and Implementation. 2nd Edition. "
    "Routledge, London."
)
add_paragraph(
    "[3] Ahmad, M., et al. (2014). Biochar as a sorbent for contaminant "
    "management in soil and water: A review. Chemosphere, 99, 19-33."
)
add_paragraph(
    "[4] Reddy, K.R., et al. (2014). Removal of heavy metals from urban "
    "stormwater runoff using biochar. Proceedings of Geo-Congress 2014, "
    "ASCE, 3045-3053."
)
add_paragraph(
    "[5] Ulrich, B.A., et al. (2015). Biochar amendment for enhanced "
    "phosphorus removal from stormwater runoff. Environmental Science "
    "and Technology, 49(7), 4060-4067."
)
add_paragraph(
    "[6] Tian, J., et al. (2019). Field-scale evaluation of biochar "
    "amended bioretention for stormwater treatment. Journal of "
    "Sustainable Water in the Built Environment, 5(4), 04019007."
)
add_paragraph(
    "[7] Mohanty, S.K., et al. (2018). Plenty of room for carbon on the "
    "ground: Potential applications of biochar for stormwater treatment. "
    "Science of the Total Environment, 625, 1644-1658."
)
add_paragraph(
    "[8] Liu, J., et al. (2020). Mechanisms of biochar-mediated "
    "contaminant immobilization in stormwater bioretention columns. "
    "Water Research, 171, 115382."
)
add_paragraph("")

# ── Budget Justification ────────────────────────────────────────────────────
add_paragraph("Budget Justification")
add_paragraph("")
add_paragraph("Category | Year 1 | Year 2 | Year 3 | Total")
add_paragraph("Senior Personnel | $45,000 | $46,350 | $47,741 | $139,091")
add_paragraph("Graduate Students | $52,000 | $53,560 | $55,167 | $160,727")
add_paragraph("Undergraduate Students | $12,000 | $12,360 | $12,731 | $37,091")
add_paragraph("Equipment | $45,000 | $15,000 | $8,000 | $68,000")
add_paragraph("Supplies | $18,000 | $16,000 | $14,000 | $48,000")
add_paragraph("Travel | $8,000 | $8,000 | $8,000 | $24,000")
add_paragraph("Other | $7,654 | $7,654 | $7,655 | $22,963")
add_paragraph("Total | $187,654 | $158,924 | $153,294 | $499,872")
add_paragraph("")
add_paragraph(
    "Senior Personnel: Dr. Vasquez will devote two summer months per year "
    "to the project. The Year 1 salary of $45,000 reflects the current "
    "institutional rate with a 3% annual escalation applied in Years 2 "
    "and 3. No academic year salary is requested."
)
add_paragraph(
    "Graduate Students: Two PhD students will be supported at "
    "$26,000/year each including tuition remission and health insurance. "
    "One student will focus on laboratory experiments and biochar "
    "characterization (Task 1), while the second will lead field "
    "monitoring and computational modeling (Tasks 2 and 3). A 3% annual "
    "escalation is included."
)
add_paragraph(
    "Undergraduate Students: Four undergraduate research assistants "
    "will be employed at $15/hour for 10 hours/week during the academic "
    "year and 20 hours/week during summer. Undergraduates will assist "
    "with laboratory analyses, field sampling, and data management."
)
add_paragraph(
    "Equipment: Year 1 includes purchase of an automated water sampler "
    "system ($25,000) and a portable X-ray fluorescence analyzer "
    "($20,000). Year 2 includes field instrumentation for the "
    "bioretention cells ($15,000). Year 3 includes replacement sensors "
    "and calibration equipment ($8,000)."
)
add_paragraph(
    "Supplies: Laboratory consumables including biochar feedstocks, "
    "filter media components, analytical reagents, sample containers, "
    "and column construction materials. Costs decrease in later years "
    "as laboratory work transitions to field monitoring."
)
add_paragraph(
    "Travel: Domestic travel to two conferences per year (AGU Fall "
    "Meeting and ASCE EWRI Congress) for PI and graduate students. "
    "Includes travel to field sites in the Portland metropolitan area."
)
add_paragraph(
    "Other: Publication costs for open-access journal articles ($3,000 "
    "per article, estimated 2-3 articles) and participant support for "
    "undergraduate summer research stipends."
)
add_paragraph("")

# ── Biographical Sketch ─────────────────────────────────────────────────────
add_paragraph("Biographical Sketch")
add_paragraph("")
add_paragraph(
    "Dr. Elena Vasquez has over 15 years of experience in environmental "
    "engineering with expertise in stormwater management, water treatment, "
    "and sustainable infrastructure design. She is currently Associate "
    "Professor and Director of the Urban Water Quality Laboratory at "
    "Pacific Northwest University."
)
add_paragraph("")
add_paragraph("Professional Preparation")
add_paragraph(
    "University of California, Berkeley - Civil and Environmental "
    "Engineering - B.S., 2005"
)
add_paragraph(
    "Stanford University - Environmental Engineering and Science - "
    "M.S., 2007"
)
add_paragraph(
    "Stanford University - Environmental Engineering and Science - "
    "Ph.D., 2011"
)
add_paragraph("")
add_paragraph("Appointments")
add_paragraph(
    "2018-present: Associate Professor, Department of Environmental "
    "Engineering, Pacific Northwest University"
)
add_paragraph(
    "2011-2018: Assistant Professor, Department of Environmental "
    "Engineering, Pacific Northwest University"
)
add_paragraph("")
add_paragraph("Selected Publications")
add_paragraph(
    "Vasquez, E., Kim, H., and Park, J. (2023). Long-term performance "
    "of bioretention systems in the Pacific Northwest: A 10-year "
    "monitoring study. Water Research, 228, 119842."
)
add_paragraph(
    "Vasquez, E. and Thompson, R. (2021). Biochar as a soil amendment "
    "for enhanced stormwater infiltration and treatment. Journal of "
    "Environmental Engineering, 147(6), 04021023."
)
add_paragraph(
    "Chen, L. and Vasquez, E. (2020). Microbial community dynamics in "
    "bioretention filter media: Effects of vegetation and maintenance "
    "practices. Environmental Science and Technology, 54(18), 11256-11265."
)
add_paragraph(
    "Vasquez, E., et al. (2019). Design optimization of bioretention "
    "systems for phosphorus removal in cold climates. Ecological "
    "Engineering, 131, 19-28."
)
add_paragraph(
    "Vasquez, E. and Martinez, A. (2017). Hydraulic and water quality "
    "performance of permeable pavement systems under Pacific Northwest "
    "rainfall conditions. Journal of Sustainable Water in the Built "
    "Environment, 3(2), 04016012."
)
add_paragraph("")
add_paragraph("Synergistic Activities")
add_paragraph(
    "1. Faculty advisor, Pacific Northwest University chapter of "
    "Engineers Without Borders, leading clean water projects in "
    "rural Guatemala (2015-present)."
)
add_paragraph(
    "2. Member, City of Portland Green Infrastructure Technical "
    "Advisory Committee (2019-present)."
)
add_paragraph(
    "3. Co-developer, open-source Bioretention Design Tool (BDT) used "
    "by over 200 municipalities nationwide."
)
add_paragraph(
    "4. Organizer, annual Green Infrastructure Workshop for K-12 "
    "teachers in partnership with the Oregon Museum of Science "
    "and Industry (2016-present)."
)
add_paragraph(
    "5. Associate Editor, Journal of Sustainable Water in the Built "
    "Environment, ASCE (2020-present)."
)

doc.save("/home/ga/Documents/nsf_proposal.odt", False)
print("Created nsf_proposal.odt")
PYEOF

chown ga:ga /home/ga/Documents/nsf_proposal.odt
chmod 0664 /home/ga/Documents/nsf_proposal.odt

# ---------------------------------------------------------------------------
# Create the NSF formatting requirements specification
# ---------------------------------------------------------------------------
cat > /home/ga/Desktop/nsf_formatting_requirements.txt << 'SPECEOF'
NSF PAPPG FORMATTING REQUIREMENTS SUMMARY
National Science Foundation - Proposal & Award Policies & Procedures Guide

1. PAGE SETUP
   - Paper size: US Letter (8.5 x 11 inches)
   - Margins: Minimum 1 inch on all sides
   - Page numbers: Bottom center of each page

2. FONT REQUIREMENTS
   - Minimum 11-point font for all text
   - Acceptable fonts: Times New Roman, Computer Modern, Arial
   - Smaller fonts NOT permitted in any section including references

3. SPACING
   - Single-spaced text is acceptable
   - No more than 6 lines per vertical inch

4. SECTION ORGANIZATION (in order)
   - Cover Page (title, PI, institution, program, amount, dates)
   - Project Summary (max 1 page, MUST contain: Overview, Intellectual Merit, Broader Impacts as labeled subsections)
   - Table of Contents
   - Project Description (max 15 pages)
   - References Cited (no page limit)
   - Budget Justification
   - Biographical Sketch

5. HEADING FORMATTING
   - Main section headings: Bold, 12pt or larger, Heading 1 style
   - Subsection headings: Bold, 11pt or larger, Heading 2 style

6. BODY TEXT
   - Justified alignment preferred for readability
   - Consistent paragraph formatting throughout

7. TABLES
   - Budget table required with columns: Category, Year 1, Year 2, Year 3, Total
   - Table headers in bold
   - All financial figures right-aligned

8. COVER PAGE
   - Proposal title: Bold, centered, 14pt or larger
   - PI name: Centered
   - Institution: Centered
   - All cover page elements centered
SPECEOF

chown ga:ga /home/ga/Desktop/nsf_formatting_requirements.txt
chmod 0644 /home/ga/Desktop/nsf_formatting_requirements.txt

echo "Launching Calligra Words..."
launch_calligra_document "/home/ga/Documents/nsf_proposal.odt" "/tmp/calligra_words_task.log"

if ! wait_for_process "/usr/bin/calligrawords" 20; then
    wait_for_process "calligrawords" 15 || true
fi

if ! wait_for_window "Calligra Words\\|nsf_proposal" 60; then
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

take_screenshot /tmp/calligra_grant_proposal_formatting_setup.png

echo "=== Grant Proposal Formatting Task Setup Complete ==="
