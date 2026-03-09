#!/bin/bash
# setup_task.sh — Clinical Protocol Amendment Task

source /workspace/scripts/task_utils.sh
chmod +x /workspace/tasks/clinical_protocol_amendment/export_result.sh 2>/dev/null || true

echo "=== Setting up Clinical Protocol Amendment Task ==="

sudo -u ga mkdir -p /home/ga/Documents

date +%s > /tmp/clinical_protocol_task_start
chown ga:ga /tmp/clinical_protocol_task_start 2>/dev/null || true

# Create protocol_v1.docx — a realistic Phase II clinical trial protocol
# with content that needs specific targeted amendments.
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

doc = Document()

# Set margins
section = doc.sections[0]
section.left_margin = Inches(1.0)
section.right_margin = Inches(1.0)
section.top_margin = Inches(1.0)
section.bottom_margin = Inches(1.0)

# --- Add header with version info (agent must update version and date) ---
header = section.header
header_para = header.paragraphs[0] if header.paragraphs else header.add_paragraph()
header_para.clear()
run = header_para.add_run(
    "HELI-CARD-201 Clinical Trial Protocol  |  Version 1.0  |  14 January 2024  |  CONFIDENTIAL"
)
run.font.size = Pt(9)
run.bold = True
header_para.alignment = WD_ALIGN_PARAGRAPH.CENTER

def h1(text):
    p = doc.add_heading(text, level=1)
    return p

def h2(text):
    p = doc.add_heading(text, level=2)
    return p

def plain(text, size=11):
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.font.size = Pt(size)
    return p

def numbered_item(text, number, size=11):
    p = doc.add_paragraph(style='List Number')
    run = p.add_run(text)
    run.font.size = Pt(size)
    return p

# ===== COVER PAGE =====
p = doc.add_paragraph()
run = p.add_run("HELI-CARD-201")
run.font.size = Pt(18)
run.bold = True
p.alignment = WD_ALIGN_PARAGRAPH.CENTER

p = doc.add_paragraph()
run = p.add_run(
    "A Phase II, Randomized, Double-Blind, Placebo-Controlled Study to Evaluate\n"
    "the Efficacy and Safety of Heliogenin-A in Patients with\n"
    "Chronic Heart Failure (NYHA Class II–III)"
)
run.font.size = Pt(12)
p.alignment = WD_ALIGN_PARAGRAPH.CENTER

doc.add_paragraph("")
plain("Sponsor: Heliogen Therapeutics, Inc., 2100 Biotech Blvd, San Francisco, CA 94107")
plain("Protocol Number: HELI-CARD-201")
plain("Version: 1.0")
plain("Date: 14 January 2024")
plain("IND Number: 147,823")
plain("EudraCT Number: 2023-005891-14")
plain("ClinicalTrials.gov: NCT05891023")

doc.add_paragraph("")

# ===== SECTION 1: Background and Rationale =====
h1("1. Background and Rationale")
plain(
    "Chronic heart failure (CHF) affects approximately 6.2 million adults in the United States "
    "(Benjamin et al., 2019, Circulation) and is associated with high morbidity, mortality, "
    "and healthcare costs exceeding $30 billion annually. Despite advances in guideline-directed "
    "medical therapy (GDMT) including angiotensin-converting enzyme inhibitors, beta-blockers, "
    "mineralocorticoid receptor antagonists, and sodium-glucose cotransporter-2 inhibitors, "
    "a significant proportion of patients continue to experience progressive cardiac remodeling "
    "and deteriorating functional status."
)
plain(
    "Heliogenin-A (HGA) is a novel, orally bioavailable small-molecule inhibitor of "
    "matrix metalloproteinase-9 (MMP-9), a key mediator of pathological cardiac extracellular "
    "matrix remodeling. In preclinical studies using the transverse aortic constriction (TAC) "
    "mouse model, HGA administration at 30 mg/kg/day for 8 weeks significantly reduced "
    "left ventricular end-diastolic diameter (LVEDD) by 23% and improved ejection fraction "
    "by 18 percentage points compared to vehicle-treated controls (Chen et al., 2022, "
    "J Cardiovasc Pharmacol). A Phase I first-in-human study (HELI-001) established a "
    "maximum tolerated dose of 50 mg twice daily with a favorable safety and tolerability "
    "profile in 36 healthy volunteers."
)

doc.add_paragraph("")

# ===== SECTION 2: Objectives =====
h1("2. Study Objectives and Endpoints")
h2("2.1 Primary Objective")
plain(
    "To evaluate the effect of Heliogenin-A 50 mg BID versus placebo on the composite "
    "endpoint of cardiovascular death or heart failure hospitalization at 52 weeks in "
    "patients with NYHA Class II–III CHF and left ventricular ejection fraction (LVEF) "
    "≤ 40% who are on stable GDMT."
)
h2("2.2 Secondary Objectives")
plain(
    "Secondary objectives include: (a) effect on change from baseline in LVEF at 26 and "
    "52 weeks by echocardiography; (b) change in NT-proBNP levels at 12, 26, and 52 weeks; "
    "(c) effect on 6-Minute Walk Test (6MWT) distance at 26 and 52 weeks; (d) change in "
    "Kansas City Cardiomyopathy Questionnaire (KCCQ) overall summary score; and "
    "(e) safety and tolerability profile including cardiac adverse events."
)

doc.add_paragraph("")

# ===== SECTION 3: Study Design =====
h1("3. Study Design")
plain(
    "This is a Phase II, randomized, double-blind, placebo-controlled, parallel-group, "
    "multicenter study in patients with CHF. Approximately 320 patients will be randomized "
    "1:1 to receive Heliogenin-A 50 mg BID or matching placebo for 52 weeks. Randomization "
    "will be stratified by NYHA class (II vs. III) and geographic region (North America, "
    "Europe, Asia-Pacific) using a permuted-block randomization scheme with block sizes "
    "of 4 and 6. The sponsor, study sites, patients, and outcome assessors will remain "
    "blinded to treatment assignment throughout the study."
)
plain(
    "The study consists of four periods: Screening (4 weeks), Run-In (2 weeks), "
    "Treatment (52 weeks), and Follow-Up (4 weeks). The total study duration per patient "
    "is approximately 62 weeks. The primary analysis will be conducted when all patients "
    "have completed 52 weeks of treatment or have discontinued early."
)

doc.add_paragraph("")

# ===== SECTION 4: Study Population =====
h1("4. Study Population")
h2("4.1 Target Population")
plain(
    "The study will enroll male and female patients, ≥ 18 years of age, with a documented "
    "diagnosis of CHF for ≥ 3 months and NYHA Class II or III symptoms at Screening. "
    "Enrollment will be conducted at approximately 45 investigational sites across "
    "North America, Europe, and Asia-Pacific."
)

doc.add_paragraph("")

# ===== SECTION 5: Inclusion/Exclusion Criteria =====
h1("5. Inclusion/Exclusion Criteria")
h2("5.1 Inclusion Criteria")
plain("Patients must meet ALL of the following criteria to be eligible:")
for crit in [
    "Age ≥ 18 years at time of informed consent",
    "Documented diagnosis of heart failure for at least 3 months prior to Screening",
    "NYHA Class II or III heart failure symptoms at the Screening Visit",
    "LVEF ≤ 40% by echocardiography within 6 months prior to Screening",
    "NT-proBNP ≥ 400 pg/mL at the Screening Visit",
    "On stable, optimized GDMT for at least 3 months, defined as stable doses of ACEi or ARB or ARNI, plus beta-blocker, plus MRA, unless contraindicated",
    "Willing and able to provide written informed consent",
    "Women of childbearing potential must have a negative serum pregnancy test at Screening and agree to use highly effective contraception throughout the study",
]:
    p = doc.add_paragraph(style='List Number')
    run = p.add_run(crit)
    run.font.size = Pt(11)

doc.add_paragraph("")

h2("5.2 Exclusion Criteria")
plain("Patients must NOT meet ANY of the following criteria to be eligible:")
for crit in [
    "Current NYHA Class IV heart failure symptoms",
    "Hospitalization for acute decompensated heart failure within 4 weeks prior to Screening",
    "Estimated glomerular filtration rate (eGFR) < 30 mL/min/1.73 m² at Screening",
    "Alanine aminotransferase (ALT) or aspartate aminotransferase (AST) > 3× upper limit of normal (ULN) at Screening",
    "Ongoing or planned cardiac resynchronization therapy (CRT) initiation or modification within 3 months of Screening",
    "Active malignancy requiring systemic therapy within 2 years prior to Screening (exceptions: basal cell carcinoma, squamous cell carcinoma of skin, carcinoma in situ of cervix)",
    "History of cardiac transplantation or implantable ventricular assist device",
    "Known hypersensitivity to Heliogenin-A or any excipient",
    "Participation in another interventional clinical trial within 30 days prior to Screening",
    "Pregnancy, lactation, or intent to become pregnant during the study period",
]:
    p = doc.add_paragraph(style='List Number')
    run = p.add_run(crit)
    run.font.size = Pt(11)

doc.add_paragraph("")

# ===== SECTION 6: Study Treatments =====
h1("6. Study Treatments")
h2("6.1 Investigational Medicinal Product")
plain(
    "Heliogenin-A will be supplied as film-coated tablets containing 50 mg of active "
    "substance per tablet. Patients randomized to the active treatment arm will receive "
    "one tablet of Heliogenin-A 50 mg orally twice daily (morning and evening) with food. "
    "Placebo tablets, identical in appearance to the active tablets, will be provided "
    "to patients randomized to the control arm."
)
h2("6.2 Dose Modifications")
plain(
    "Dose reductions are permitted for hepatotoxicity (ALT or AST > 3× ULN) and renal "
    "impairment (eGFR decline > 30% from baseline persisting for > 2 weeks). No dose "
    "reductions are permitted for other adverse events; study drug discontinuation is "
    "required for intolerable adverse events. A maximum of one dose reduction per patient "
    "is permitted over the course of the study."
)

doc.add_paragraph("")

# ===== SECTION 7: Efficacy Assessments =====
h1("7. Efficacy Assessments")
plain(
    "Efficacy assessments will be conducted at Screening, Baseline (Day 1), Week 12, "
    "Week 26, Week 40, Week 52, and End of Study (Week 56). Echocardiographic assessments "
    "will be performed at Baseline, Week 26, and Week 52 by a certified cardiac sonographer "
    "and read centrally by an independent core echocardiography laboratory blinded to "
    "treatment assignment. NT-proBNP will be measured by central laboratory at all "
    "scheduled visits. The 6MWT and KCCQ will be administered per standardized protocol "
    "at Baseline, Week 26, and Week 52."
)

doc.add_paragraph("")

# ===== SECTION 8: Safety Monitoring =====
h1("8. Safety Monitoring")
h2("8.1 Data Safety Monitoring Board")
plain(
    "An independent Data Safety Monitoring Board (DSMB) has been constituted to provide "
    "ongoing safety surveillance throughout the trial. The DSMB will conduct pre-specified "
    "safety reviews after the first 50, 100, and 200 patients have completed 12 weeks of "
    "treatment. The DSMB operates under a separate DSMB Charter and has authority to "
    "recommend study modification, suspension, or termination based on safety data."
)
h2("8.2 Stopping Rules")
plain(
    "The study will be placed on clinical hold and new enrollment suspended if the DSMB "
    "determines that any of the following safety signals have been observed: "
    "(a) two (2) or more cases of Grade 3 or higher cardiac adverse events (as defined "
    "by CTCAE v5.0) in the Heliogenin-A arm that are considered at least possibly related "
    "to study drug; (b) any confirmed case of Torsades de Pointes or ventricular "
    "fibrillation; (c) a statistically significant difference in all-cause mortality "
    "between treatment arms at any interim review (p < 0.001, O'Brien-Fleming boundary)."
)
h2("8.3 Adverse Event Reporting")
plain(
    "All adverse events (AEs), including serious adverse events (SAEs), will be recorded "
    "from the time of informed consent through the end of the Follow-Up period. SAEs must "
    "be reported to the sponsor within 24 hours of the investigator becoming aware. "
    "SAEs that are unexpected and at least possibly related to study drug must be reported "
    "to regulatory authorities within 7 days (fatal/life-threatening) or 15 days (all other) "
    "in accordance with 21 CFR 312.32 and EU Clinical Trials Regulation (EU) No 536/2014."
)

doc.add_paragraph("")

# ===== SECTION 9: Statistical Analysis =====
h1("9. Statistical Analysis")
h2("9.1 Analysis Populations")
plain(
    "The Intent-to-Treat (ITT) population includes all randomized patients. The "
    "Per-Protocol (PP) population excludes patients with major protocol deviations "
    "predefined in the Statistical Analysis Plan (SAP). Safety analyses will be conducted "
    "in all patients who received at least one dose of study treatment."
)
h2("9.2 Primary Analysis")
plain(
    "The primary endpoint (time to first cardiovascular death or HF hospitalization) will "
    "be analyzed using a log-rank test stratified by NYHA class and geographic region, "
    "with a two-sided significance level of 0.05. The hazard ratio and 95% confidence "
    "interval will be estimated using a stratified Cox proportional hazards model. "
    "The study has 85% power to detect a 30% relative risk reduction (hazard ratio 0.70) "
    "assuming a 24-month event rate of 30% in the placebo arm."
)
h2("9.3 Multiplicity Control")
plain(
    "A hierarchical testing procedure will be used to control the family-wise Type I error "
    "rate for secondary endpoints. The secondary endpoints will be tested in the order "
    "specified in Section 2.2 only if the primary endpoint is statistically significant. "
    "No alpha correction will be applied to exploratory endpoints."
)

doc.add_paragraph("")

# ===== SECTION 10: Ethical Considerations =====
h1("10. Ethical Considerations")
plain(
    "This study will be conducted in accordance with the ethical principles of the "
    "Declaration of Helsinki (2013 amendment), International Council for Harmonisation "
    "Good Clinical Practice (ICH E6(R2)) guidelines, and applicable regulatory "
    "requirements. Approval from an institutional review board (IRB) or independent ethics "
    "committee (IEC) at each site is required prior to initiation of study procedures. "
    "Written informed consent must be obtained from all patients prior to any study-specific "
    "procedures."
)

doc.add_paragraph("")

# ===== SECTION 11: References =====
h1("11. References")
for ref in [
    "Benjamin EJ, et al. Heart Disease and Stroke Statistics—2019 Update. Circulation. 2019;139(10):e56-e528.",
    "Chen L, et al. MMP-9 inhibition by Heliogenin-A attenuates cardiac remodeling in a murine model of pressure overload. J Cardiovasc Pharmacol. 2022;80(3):210-220.",
    "McDonagh TA, et al. 2021 ESC Guidelines for the diagnosis and treatment of acute and chronic heart failure. Eur Heart J. 2021;42(36):3599-3726.",
    "Packer M, et al. Cardiovascular and Renal Outcomes with Empagliflozin in Heart Failure. N Engl J Med. 2020;383(15):1413-1424.",
    "ICH E6(R2) Guideline for Good Clinical Practice. International Council for Harmonisation, 2016.",
]:
    p = doc.add_paragraph(style='List Bullet')
    run = p.add_run(ref)
    run.font.size = Pt(10)

doc.add_paragraph("")

# ===== APPENDIX: Version History Table =====
h1("Appendix A: Version History")
table = doc.add_table(rows=2, cols=3)
table.style = 'Table Grid'
# Header
hdr = table.rows[0].cells
hdr[0].text = "Version"
hdr[1].text = "Date"
hdr[2].text = "Description of Changes"
for cell in hdr:
    for para in cell.paragraphs:
        for run in para.runs:
            run.bold = True
# v1.0 row
row1 = table.rows[1].cells
row1[0].text = "1.0"
row1[1].text = "14 January 2024"
row1[2].text = "Initial version"

doc.save("/home/ga/Documents/protocol_v1.docx")
print("Created protocol_v1.docx")
PYEOF

sudo chown ga:ga /home/ga/Documents/protocol_v1.docx
sudo chmod 664 /home/ga/Documents/protocol_v1.docx

echo "Launching LibreOffice Writer with protocol_v1.docx..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/protocol_v1.docx > /tmp/writer_protocol_task.log 2>&1 &"

if ! wait_for_process "soffice" 20; then
    echo "ERROR: LibreOffice failed to start"
fi

if ! wait_for_window "LibreOffice Writer" 90; then
    wait_for_window "protocol_v1" 30 || true
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

echo "=== Clinical Protocol Amendment Task Setup Complete ==="
echo "Source: /home/ga/Documents/protocol_v1.docx"
echo "Required output: /home/ga/Documents/protocol_v2.docx"
exit 0
