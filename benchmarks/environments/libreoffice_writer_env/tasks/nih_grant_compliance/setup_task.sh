#!/bin/bash
# setup_task.sh — NIH R01 Grant Compliance Reformatting Task

source /workspace/scripts/task_utils.sh
chmod +x /workspace/tasks/nih_grant_compliance/export_result.sh 2>/dev/null || true

echo "=== Setting up NIH Grant Compliance Task ==="

sudo -u ga mkdir -p /home/ga/Documents

# Record task start timestamp for verifier
date +%s > /tmp/nih_grant_task_start
chown ga:ga /tmp/nih_grant_task_start 2>/dev/null || true

# Create the non-compliant r01_draft.docx with wrong font (Liberation Serif 10pt)
# and wrong margins (1 inch). No heading styles, no header, no hanging indent.
# Content is based on real tumor microenvironment immunotherapy R01 research areas.
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt, Inches, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# Set non-compliant margins: 1 inch (NIH requires >= 0.5 inch — this is fine but
# the font and style are wrong, which is the main compliance issue)
section = doc.sections[0]
section.left_margin = Inches(1.0)
section.right_margin = Inches(1.0)
section.top_margin = Inches(1.0)
section.bottom_margin = Inches(1.0)

# Helper: add a plain paragraph with wrong font (no style applied)
def add_plain(text, bold=False, size=10):
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.font.name = "Liberation Serif"
    run.font.size = Pt(size)
    run.bold = bold
    return p

def add_section_heading(title):
    """Add section heading as plain bold text — no Heading style applied."""
    p = doc.add_paragraph()
    run = p.add_run(title)
    run.font.name = "Liberation Serif"
    run.font.size = Pt(11)
    run.bold = True
    return p

# --- Abstract ---
add_section_heading("Abstract")
add_plain(
    "The tumor microenvironment (TME) plays a critical role in modulating anti-tumor "
    "immune responses and the efficacy of checkpoint immunotherapy. Despite remarkable "
    "clinical responses in a subset of patients with advanced solid tumors, the majority "
    "of patients fail to respond to PD-1/PD-L1 blockade, and the mechanisms underlying "
    "primary and acquired resistance remain incompletely understood. Our preliminary data "
    "demonstrate that tumor-infiltrating myeloid cells — specifically immunosuppressive "
    "tumor-associated macrophages (TAMs) and myeloid-derived suppressor cells (MDSCs) — "
    "create a profoundly immunosuppressive milieu that impairs CD8+ T cell function and "
    "limits immunotherapy efficacy. We have identified a novel signaling axis, SIRPα/CD47, "
    "that governs myeloid polarization and promotes immune exclusion of T cells within "
    "the TME of triple-negative breast cancer (TNBC) and non-small cell lung cancer (NSCLC). "
    "This proposal tests the central hypothesis that pharmacological disruption of SIRPα "
    "signaling reprograms TAMs from an immunosuppressive M2-like phenotype to a pro-inflammatory "
    "M1-like phenotype, thereby restoring T cell-mediated tumor killing and sensitizing "
    "tumors to anti-PD-1 therapy. We will pursue this hypothesis through three integrated "
    "Specific Aims using genetically engineered mouse models, patient-derived tumor organoids, "
    "and a Phase Ib clinical trial in patients with PD-L1-positive TNBC and NSCLC."
)

doc.add_paragraph("")

# --- Specific Aims ---
add_section_heading("Specific Aims")
add_plain(
    "Immunotherapy with anti-PD-1/PD-L1 antibodies has transformed the treatment landscape "
    "for multiple solid tumor types. However, durable responses are achieved in only 20-40% "
    "of unselected patients, underscoring the need to understand and overcome intrinsic and "
    "extrinsic mechanisms of resistance. Emerging evidence implicates immunosuppressive myeloid "
    "cells as key mediators of immune exclusion and checkpoint blockade resistance. The "
    "SIRPα/CD47 'don't-eat-me' signaling axis, originally characterized as a regulator of "
    "macrophage phagocytosis, is now recognized as a master regulator of myeloid cell "
    "polarization and a critical determinant of T cell priming efficiency within tumor-draining "
    "lymph nodes. Our preliminary data show that SIRPα blockade using the humanized monoclonal "
    "antibody CC-95251 reduces tumor burden in syngeneic murine models of TNBC and NSCLC by "
    "up to 73% as a single agent and produces complete responses in 42% of animals when "
    "combined with anti-PD-1. These findings form the preclinical rationale for this proposal."
)
add_plain(
    "Aim 1: Define the mechanistic basis by which SIRPα signaling drives TAM immunosuppression "
    "and CD8+ T cell exclusion in TNBC and NSCLC. We will use single-cell RNA sequencing "
    "(scRNA-seq), CITE-seq, and spatial transcriptomics to characterize myeloid cell states "
    "in SIRPα wild-type versus SIRPα-knockout tumor-bearing mice and in paired pre/post-treatment "
    "tumor biopsies from patients enrolled in the clinical trial (Aim 3)."
)
add_plain(
    "Aim 2: Determine whether SIRPα blockade restores intratumoral T cell function and "
    "synergizes with anti-PD-1 therapy through myeloid reprogramming. Using adoptive transfer "
    "of antigen-specific T cells and ex vivo tumor organoid-immune co-culture systems, we "
    "will quantify T cell killing capacity after SIRPα blockade with and without anti-PD-1."
)
add_plain(
    "Aim 3: Conduct a Phase Ib dose-escalation trial of CC-95251 in combination with "
    "pembrolizumab in patients with PD-L1-positive TNBC or NSCLC. Primary endpoints are "
    "safety/tolerability and maximum tolerated dose (MTD). Secondary endpoints include "
    "objective response rate (ORR), progression-free survival (PFS), and correlative "
    "biomarker analyses (circulating MDSCs, serum CD47, tumor-infiltrating lymphocytes)."
)

doc.add_paragraph("")

# --- Research Strategy ---
add_section_heading("Research Strategy")
add_plain(
    "Significance. Triple-negative breast cancer (TNBC) and non-small cell lung cancer "
    "(NSCLC) together account for approximately 250,000 new diagnoses annually in the "
    "United States (SEER Database, 2023). Despite the approval of pembrolizumab plus "
    "chemotherapy for first-line treatment of PD-L1-positive metastatic TNBC (KEYNOTE-522) "
    "and NSCLC (KEYNOTE-024), the majority of patients still progress on front-line immunotherapy. "
    "Median overall survival for metastatic TNBC remains 13 months, and 5-year survival for "
    "Stage IV NSCLC is approximately 8%. There is therefore an urgent and unmet clinical need "
    "to identify rational immunotherapy combinations that overcome resistance mechanisms. "
    "Our work identifies TAM reprogramming via SIRPα blockade as a mechanistically distinct, "
    "clinically actionable strategy that does not depend on pre-existing T cell infiltration, "
    "thereby potentially benefiting the 60% of tumors classified as 'immunologically cold.'"
)

doc.add_paragraph("")

# --- Innovation ---
add_section_heading("Innovation")
add_plain(
    "This proposal is innovative in three respects. First, it positions SIRPα/CD47 blockade "
    "as a myeloid reprogramming strategy rather than solely a phagocytosis checkpoint, "
    "representing a conceptual advance beyond current literature. Second, the integration "
    "of spatial transcriptomics (10x Visium) with standard scRNA-seq will provide "
    "unprecedented resolution of the spatially compartmentalized immune landscape and the "
    "specific niches within which TAMs suppress T cell function. Third, this is among the "
    "first prospective biomarker-embedded Phase Ib trials to evaluate SIRPα-directed therapy "
    "in combination with anti-PD-1, enabling translational validation of mechanistic findings "
    "from Aims 1 and 2 within the same grant period."
)

doc.add_paragraph("")

# --- Approach ---
add_section_heading("Approach")
add_plain(
    "General experimental design. All murine experiments will use female C57BL/6J (8-12 weeks) "
    "with syngeneic E0771 (TNBC) or LLC1 (NSCLC) tumors implanted subcutaneously. Tumor "
    "volume will be measured by digital calipers three times weekly (V = 0.5 × L × W²). "
    "Mice will be randomized to treatment arms when tumors reach 100-150 mm³. SIRPα-KO mice "
    "(B6.129S7-Sirpatm1Mtc/J) obtained from Jackson Laboratories will serve as a genetic "
    "ablation model. CC-95251 (provided under MTA from Bristol Myers Squibb) will be "
    "administered IP at 10 mg/kg twice weekly. Anti-mouse PD-1 (clone RMP1-14, BioXCell) "
    "will be administered IP at 200 µg per dose on days 3, 6, and 9 post-implantation."
)
add_plain(
    "Power analysis. Based on our pilot data showing a 73% reduction in tumor volume with "
    "SIRPα blockade alone (SD = 18%), we estimate n=8 per group provides 90% power to detect "
    "a 40% difference between treatment arms at α=0.05 (two-tailed t-test). All animal "
    "experiments have been approved by the IACUC (Protocol 2023-0456). Patient-derived tumor "
    "organoids will be established from fresh surgical resections (n=30 TNBC, n=30 NSCLC) "
    "following IRB-approved consent (Protocol 2023-1124). The Phase Ib trial (NCT05823701) "
    "will enroll 36 patients in a 3+3 dose-escalation design across four dose levels "
    "(1, 3, 10, 20 mg/kg CC-95251 IV Q2W) with pembrolizumab 200 mg IV Q3W."
)

doc.add_paragraph("")

# --- References (no hanging indent — agent must apply it) ---
add_section_heading("References")
refs = [
    "Chen DS, Mellman I. Elements of cancer immunity and the cancer-immune set point. "
    "Nature. 2017;541(7637):321-330. doi:10.1038/nature21349.",

    "Binnewies M, Roberts EW, Kersten K, et al. Understanding the tumor immune microenvironment "
    "(TIME) for effective therapy. Nat Med. 2018;24(5):541-550. doi:10.1038/s41591-018-0014-x.",

    "Veglia F, Sanseviero E, Bhardwaj N, Gabrilovich DI. Myeloid-derived suppressor cells in "
    "the era of increasing myeloid cell diversity. Nat Rev Immunol. 2021;21(8):485-498. "
    "doi:10.1038/s41577-020-00490-y.",

    "Willingham SB, Volkmer JP, Gentles AJ, et al. The CD47-signal regulatory protein alpha "
    "(SIRPa) interaction is a therapeutic target for human solid tumors. Proc Natl Acad Sci USA. "
    "2012;109(17):6662-6667. doi:10.1073/pnas.1121623109.",

    "Liu X, Pu Y, Cron K, et al. CD47 blockade triggers T cell-mediated destruction of "
    "immunogenic tumors. Nat Med. 2015;21(10):1209-1215. doi:10.1038/nm.3931.",

    "Cordes N, Frey B, Gaipl US, Rückert M. Myeloid cell-centric mechanisms of resistance "
    "to immune checkpoint therapy in cancer. Cancer Lett. 2022;534:215612. "
    "doi:10.1016/j.canlet.2022.215612.",

    "Schmid P, Adams S, Rugo HS, et al. Atezolizumab and nab-paclitaxel in advanced "
    "triple-negative breast cancer. N Engl J Med. 2018;379(22):2108-2121. "
    "doi:10.1056/NEJMoa1809615.",

    "Reck M, Rodríguez-Abreu D, Robinson AG, et al. Pembrolizumab versus chemotherapy for "
    "PD-L1-positive non-small-cell lung cancer. N Engl J Med. 2016;375(19):1823-1833. "
    "doi:10.1056/NEJMoa1606774.",
]
for ref in refs:
    add_plain(ref)

doc.save("/home/ga/Documents/r01_draft.docx")
print("Created r01_draft.docx (non-compliant format)")
PYEOF

sudo chown ga:ga /home/ga/Documents/r01_draft.docx
sudo chmod 664 /home/ga/Documents/r01_draft.docx

# Launch LibreOffice Writer with the draft document
echo "Launching LibreOffice Writer with r01_draft.docx..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/r01_draft.docx > /tmp/writer_nih_task.log 2>&1 &"

if ! wait_for_process "soffice" 20; then
    echo "ERROR: LibreOffice failed to start"
fi

if ! wait_for_window "LibreOffice Writer" 90; then
    wait_for_window "r01_draft" 30 || true
fi

sleep 2

# Focus Writer and dismiss any startup dialogs
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    safe_xdotool ga :1 key Escape
    sleep 0.3
    safe_xdotool ga :1 key ctrl+Home
    sleep 0.3
fi

# Record task start timestamp (required for adversarial robustness)
date +%s > /tmp/task_start_timestamp

# Take initial screenshot using ImageMagick import (scrot not in root PATH)
import -window root /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== NIH Grant Compliance Task Setup Complete ==="
echo "Source document: /home/ga/Documents/r01_draft.docx"
echo "Required output: /home/ga/Documents/r01_formatted.docx"
echo "Compliance requirements: NIH PA-23-093 (Arial/Helvetica/Georgia/Palatino 11pt+, 0.5in margins, Heading 1 for 6 sections, hanging indent for references, header with grant info)"
exit 0
