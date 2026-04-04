#!/bin/bash
# setup_task.sh — Engineering Inspection Report Formatting Task

source /workspace/scripts/task_utils.sh
chmod +x /workspace/tasks/engineering_inspection_report/export_result.sh 2>/dev/null || true

echo "=== Setting up Engineering Inspection Report Task ==="

sudo -u ga mkdir -p /home/ga/Documents

date +%s > /tmp/engineering_inspection_task_start
chown ga:ga /tmp/engineering_inspection_task_start 2>/dev/null || true

# Create inspection_draft.docx — a field notes draft with plain text,
# no styles, no tables for observations/calculations, no PE certification box.
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

section = doc.sections[0]
section.left_margin = Inches(1.0)
section.right_margin = Inches(1.0)
section.top_margin = Inches(1.0)
section.bottom_margin = Inches(1.0)

def plain(text, bold=False, size=11):
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.font.size = Pt(size)
    run.bold = bold
    return p

def sec_head(text):
    """Plain bold heading — no Heading style applied."""
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.font.size = Pt(12)
    run.bold = True
    return p

def sub_head(text):
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.font.size = Pt(11)
    run.bold = True
    return p

# --- Cover ---
p = doc.add_paragraph()
run = p.add_run("STRUCTURAL CONDITION ASSESSMENT REPORT")
run.font.size = Pt(16)
run.bold = True
p.alignment = WD_ALIGN_PARAGRAPH.CENTER

p = doc.add_paragraph()
run = p.add_run("Riverside Office Complex")
run.font.size = Pt(13)
p.alignment = WD_ALIGN_PARAGRAPH.CENTER

p = doc.add_paragraph()
run = p.add_run("1234 Commerce Drive, Austin, Texas 78701")
run.font.size = Pt(11)
p.alignment = WD_ALIGN_PARAGRAPH.CENTER

doc.add_paragraph("")
plain("Prepared by: Caldwell & Associates Structural Engineering")
plain("Project Number: CA-2024-1089")
plain("Assessment Date: October 3–4, 2024")
plain("Report Date: October 18, 2024")
plain("Client: Riverside Commerce Partners LLC")
plain("PE of Record: Michael T. Caldwell, PE | License No. TX-78234")

doc.add_paragraph("")

# --- Section 1: Introduction ---
sec_head("Introduction")
plain(
    "Caldwell & Associates Structural Engineering (CASE) was retained by Riverside Commerce "
    "Partners LLC to conduct a structural condition assessment of the Riverside Office Complex "
    "at 1234 Commerce Drive, Austin, Texas 78701. The assessment was performed in response "
    "to reported cracking in concrete columns on the ground floor and water intrusion in "
    "the parking structure. The purpose of this assessment is to evaluate the structural "
    "integrity of the building, identify deficiencies, and provide recommendations for remediation."
)
plain(
    "The assessment was performed on October 3–4, 2024, by Michael T. Caldwell, PE, and "
    "James R. Holloway, EIT. This report presents our findings and recommendations based "
    "on visual observation, measurements, and review of the original structural drawings "
    "(Architect of Record: Harrison-Patel Architecture, 2003; Structural Engineer of Record: "
    "Morrison Structural Group, Permit Set dated March 15, 2003). No destructive testing "
    "was performed as part of this assessment."
)

doc.add_paragraph("")

# --- Section 2: Scope ---
sec_head("Scope of Assessment")
sub_head("2.1 Included in Scope")
plain(
    "The scope of this structural condition assessment includes: (a) visual observation "
    "of all accessible structural members including columns, beams, slabs, shear walls, "
    "and foundation-grade beam connections at grade level; (b) measurement of crack widths "
    "and documentation of deterioration patterns in the reinforced concrete parking structure "
    "(Levels P1 and P2); (c) review of original structural drawings and specifications; "
    "(d) comparison of observed conditions against applicable design standards, specifically "
    "ACI 318-19 (Building Code Requirements for Structural Concrete) and ASCE 7-22 "
    "(Minimum Design Loads and Associated Criteria for Buildings and Other Structures)."
)
sub_head("2.2 Limitations")
plain(
    "This assessment is limited to visually accessible structural elements. No exploratory "
    "demolition, core sampling, or pull-out testing was performed. Subsurface conditions, "
    "foundation performance, and concealed structural members are beyond the scope of this "
    "report. Quantitative load testing was not performed. The findings and recommendations "
    "in this report are based on the conditions observed on the assessment dates and may "
    "not reflect conditions that develop subsequent to the assessment."
)

doc.add_paragraph("")

# --- Section 3: Building Description ---
sec_head("Building Description")
plain(
    "The Riverside Office Complex is a five-story, cast-in-place reinforced concrete "
    "office building with two levels of below-grade parking (P1 and P2). The structure "
    "was constructed in 2004 under building permit B2003-7821. The building has a "
    "rectangular floor plate of approximately 220 feet × 110 feet (gross floor area: "
    "approximately 121,000 sf above grade). The structural system consists of a flat-plate "
    "concrete floor/roof system supported by concrete columns on a 25-foot × 25-foot "
    "grid, with perimeter concrete shear walls providing lateral resistance."
)
plain(
    "The parking structure (P1 and P2) covers the full footprint of the building and "
    "extends approximately 15 feet below grade. The P1 level slab serves as the ground "
    "floor of the occupied office building. The original design specifies 5,000 psi "
    "normal-weight concrete for all structural elements, with Grade 60 (ASTM A615) "
    "reinforcing steel. The building underwent a tenant improvement renovation in 2018 "
    "that included interior partition modifications; no structural modifications were "
    "permitted under that renovation permit."
)

doc.add_paragraph("")

# --- Section 4: Structural Observations ---
sec_head("Structural Observations")
plain(
    "The following observations document structural deficiencies identified during the "
    "field assessment. Deficiency severity is classified as Critical (immediate safety risk, "
    "potential life safety concern), Major (significant structural concern requiring "
    "prioritized remediation within 90 days), or Minor (cosmetic or maintenance issue "
    "with no immediate structural consequence)."
)
doc.add_paragraph("")

# All 7 observations as plain text (agent must convert to 3-column tables)
plain("OBS-001 (Critical):")
plain("Location: P1 Level, Column Line E-4")
plain("Deficiency Description: Longitudinal crack in column shaft, width measured at 0.032 inches (0.81 mm) — exceeding the ACI 318-19 §24.3 serviceability limit for exterior exposure of 0.013 inches. Crack extends approximately 48 inches vertically along northeast face. Concrete spalling observed at crack perimeter exposing approximately 3.5 square inches of reinforcing steel with active corrosion products.")
plain("Recommended Action: Immediate temporary shoring of P1 slab at column E-4. Full petrographic analysis and rebar condition survey required within 30 days. Structural repair design by licensed PE required prior to restoring full column loading. Interim use restriction: do not park vehicles within 15 feet of column E-4.")

doc.add_paragraph("")
plain("OBS-002 (Critical):")
plain("Location: P2 Level, Ramp to P1, Northwest corner")
plain("Deficiency Description: Active water infiltration through construction joint at P2 slab-to-shear-wall interface. Measured chloride concentration at rebar depth: 0.72 lbs/cy (exceeds ASTM C1202 threshold of 0.60 lbs/cy for corrosion initiation). Evidence of alkali-silica reaction (ASR) gel deposits at joint perimeter. Three delaminated areas of slab soffit totaling approximately 18 square feet.")
plain("Recommended Action: Immediate removal of delaminated concrete. Apply temporary waterproof membrane over joint. Engage waterproofing specialist for permanent repair design. Core sampling required at three additional locations to characterize chloride profile.")

doc.add_paragraph("")
plain("OBS-003 (Major):")
plain("Location: Level 3 Floor Slab, Column Strip between Lines D-3 and D-4")
plain("Deficiency Description: Punching shear crack pattern observed at column D-3 capital. Radial cracking emanating from column perimeter at 45-degree intervals consistent with incipient punching shear failure. Maximum crack width: 0.015 inches. No evidence of prior repair.")
plain("Recommended Action: Install post-installed carbon-fiber reinforced polymer (CFRP) shear reinforcement in accordance with ACI 440.2R-17 within 60 days. Load restrictions: limit live load on Level 3 to 40 psf until repairs are completed. Structural analysis required to confirm adequacy of proposed CFRP retrofit.")

doc.add_paragraph("")
plain("OBS-004 (Major):")
plain("Location: P1 Level, All Column Lines A through G")
plain("Deficiency Description: Chloride-induced rebar corrosion in 24 of 63 P1 columns inspected (38%). Half-cell potential measurements ranging from -310 mV to -420 mV (CSE) indicate high to certain probability of active corrosion per ASTM C876. Concrete carbonation depth measured at 32-45 mm, approaching the nominal rebar cover of 40 mm specified in original drawings.")
plain("Recommended Action: Full electrochemical assessment of all P1 columns. Apply cathodic protection system to P1 level per NACE SP0290-2007 within 12 months. Repair spalled areas with low-permeability, chloride-resistant repair mortar meeting ASTM C928.")

doc.add_paragraph("")
plain("OBS-005 (Major):")
plain("Location: Penthouse Level, Mechanical Equipment Pad")
plain("Deficiency Description: Mechanical equipment pad on penthouse level shows deflection of L/220 (measured 0.65 inches over 12-foot span), exceeding the ACI 318-19 §24.2 long-term deflection limit of L/240 for members supporting non-structural elements not likely to be damaged by large deflections. Crack pattern consistent with long-term creep and shrinkage.")
plain("Recommended Action: Structural analysis of equipment pad under actual sustained loads required. If confirmed excessive, provide supplemental support columns or transfer to adjacent slab area with lower load demand.")

doc.add_paragraph("")
plain("OBS-006 (Minor):")
plain("Location: Levels 1-5, Perimeter Spandrel Beams")
plain("Deficiency Description: Hairline cracking (< 0.005 inches) at mid-span of perimeter spandrel beams, typical pattern consistent with shrinkage and temperature effects. No active leakage. Crack widths are within ACI 318-19 acceptable limits for interior exposure.")
plain("Recommended Action: Seal cracks with low-viscosity epoxy injection to prevent moisture intrusion and future deterioration. Re-apply elastomeric sealant at perimeter caulk joints.")

doc.add_paragraph("")
plain("OBS-007 (Minor):")
plain("Location: Ground Level, East Entrance Canopy")
plain("Deficiency Description: Two anchor bolts at east entrance canopy HSS column base plates exhibit surface rust with light pitting. Measured section loss: < 5% of original diameter. HSS column is plumb within 1/8 inch over 12-foot height (acceptable per AISC 303-22 §7.13).")
plain("Recommended Action: Wire brush rust, apply zinc-rich primer, and recoat with epoxy topcoat. Annual inspection of anchor bolt condition recommended.")

doc.add_paragraph("")

# Figure captions as plain text (agent must apply Caption style)
plain("[Figure 1: Crack pattern at Column E-4, P1 Level — photo taken October 3, 2024]")
plain("[Figure 2: Half-cell potential contour map, P1 Level column grid]")
plain("[Figure 3: Delaminated slab soffit at P2 ramp joint, northwest corner]")
plain("[Figure 4: Punching shear crack pattern at Column D-3, Level 3]")
plain("[Figure 5: Mechanical equipment pad deflection measurement, penthouse level]")

doc.add_paragraph("")

# --- Section 5: Structural Calculations ---
sec_head("Structural Calculations")
plain(
    "The following calculations were performed to confirm structural adequacy and support "
    "the recommendations in Section 4. All calculations are in accordance with "
    "ACI 318-19 and ASCE 7-22."
)
doc.add_paragraph("")

sub_head("5.1 Column E-4 Reduced Capacity (Cracking)")
plain("Parameter: Net cross-section area | Value: 186 | Unit: in² | Code Reference: ACI 318-19 §22.4.2")
plain("Parameter: Concrete compressive strength (f'c) | Value: 4,500 | Unit: psi | Code Reference: Petrographic analysis, CA-2024-1089")
plain("Parameter: Nominal axial capacity (ΦPn) | Value: 2,847 | Unit: kips | Code Reference: ACI 318-19 Eq. 22.4.2.1")
plain("Parameter: Estimated existing load (from tributary area analysis) | Value: 1,640 | Unit: kips | Code Reference: ASCE 7-22 §4.3.1")
plain("Parameter: Demand-to-capacity ratio | Value: 0.576 | Unit: dimensionless | Code Reference: ACI 318-19 §22.4.2")

doc.add_paragraph("")
sub_head("5.2 Punching Shear Capacity — Column D-3")
plain("Parameter: Column D-3 critical perimeter (b₀) | Value: 124.0 | Unit: in | Code Reference: ACI 318-19 §22.6.4.1")
plain("Parameter: Effective depth (d) | Value: 9.25 | Unit: in | Code Reference: As-built drawings")
plain("Parameter: Nominal punching shear strength (Vn) | Value: 412 | Unit: kips | Code Reference: ACI 318-19 Eq. 22.6.5.2")
plain("Parameter: Factored shear demand (Vu) | Value: 398 | Unit: kips | Code Reference: Tributary load analysis")
plain("Parameter: Demand-to-capacity ratio (Vu/ΦVn) | Value: 1.07 | Unit: dimensionless | Code Reference: ACI 318-19 §22.6.1")
plain("NOTE: DCR > 1.0 indicates inadequate punching shear capacity. CFRP retrofit required.")

doc.add_paragraph("")
sub_head("5.3 Equipment Pad Long-Term Deflection")
plain("Parameter: Span length (l) | Value: 144 | Unit: in | Code Reference: ACI 318-19 §24.2")
plain("Parameter: Immediate deflection (Δi) | Value: 0.22 | Unit: in | Code Reference: Calculated per ACI 318-19 Eq. 24.2.3.1")
plain("Parameter: Long-term deflection multiplier (λΔ) | Value: 2.0 | Unit: dimensionless | Code Reference: ACI 318-19 §24.2.4")
plain("Parameter: Total long-term deflection (Δlt) | Value: 0.66 | Unit: in | Code Reference: ACI 318-19 §24.2.4")
plain("Parameter: Allowable deflection (l/240) | Value: 0.60 | Unit: in | Code Reference: ACI 318-19 Table 24.2.2")
plain("NOTE: Δlt (0.66 in) > allowable (0.60 in) — deflection exceeds ACI 318-19 limit.")

doc.add_paragraph("")

# --- Section 6: Conclusions ---
sec_head("Conclusions and Recommendations")
plain(
    "Based on the structural condition assessment conducted on October 3–4, 2024, the "
    "Riverside Office Complex has reached an advanced state of chloride-induced deterioration "
    "in the below-grade parking structure, with two conditions (OBS-001 and OBS-002) "
    "classified as Critical and requiring immediate action. The following priority-ordered "
    "actions are recommended:"
)
for rec in [
    "IMMEDIATE (within 7 days): Install temporary shoring at Column E-4 (OBS-001). Establish 15-foot exclusion zone. Engage geotechnical engineer to evaluate parking structure drainage.",
    "30-DAY PRIORITY: Commission petrographic analysis and rebar condition survey for Column E-4. Engage waterproofing specialist for P2 ramp joint repair design (OBS-002). Perform supplemental half-cell potential survey of all P1 columns.",
    "60-DAY PRIORITY: Design and install CFRP punching shear retrofit at Column D-3 (OBS-003). Implement load restrictions on Level 3 until retrofit is complete.",
    "12-MONTH PROGRAM: Install cathodic protection system on P1 level. Implement comprehensive concrete repair program for all identified deterioration. Establish ongoing annual inspection program per ACI 364.1R-19 guidelines.",
]:
    p = doc.add_paragraph(style='List Bullet')
    run = p.add_run(rec)
    run.font.size = Pt(11)

doc.add_paragraph("")

# --- Section 7: PE Certification (plain text — agent must put in bordered table) ---
sec_head("Professional Engineer Certification")
plain("I hereby certify that this structural assessment was prepared by me or under my direct supervision, and that I am a duly licensed Professional Engineer under the laws of the State of Texas.")
plain("PE Name: Michael T. Caldwell, PE")
plain("PE License Number: TX-78234")
plain("Firm: Caldwell & Associates Structural Engineering")
plain("Date of Report: October 18, 2024")
plain("Signature: ____________________________________")
plain("Seal: [PE Seal Placeholder]")

doc.save("/home/ga/Documents/inspection_draft.docx")
print("Created inspection_draft.docx")
PYEOF

sudo chown ga:ga /home/ga/Documents/inspection_draft.docx
sudo chmod 664 /home/ga/Documents/inspection_draft.docx

echo "Launching LibreOffice Writer with inspection_draft.docx..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/inspection_draft.docx > /tmp/writer_inspection_task.log 2>&1 &"

if ! wait_for_process "soffice" 20; then
    echo "ERROR: LibreOffice failed to start"
fi

if ! wait_for_window "LibreOffice Writer" 90; then
    wait_for_window "inspection_draft" 30 || true
fi

sleep 2

wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    safe_xdotool ga :1 key Escape
    sleep 0.3
    safe_xdotool ga :1 key ctrl+Home
fi

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Take initial screenshot using ImageMagick import (scrot not in root PATH)
import -window root /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Engineering Inspection Report Task Setup Complete ==="
echo "Source: /home/ga/Documents/inspection_draft.docx"
echo "Required output: /home/ga/Documents/inspection_report.docx"
exit 0
