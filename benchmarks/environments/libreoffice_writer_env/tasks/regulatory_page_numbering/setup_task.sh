#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up regulatory_page_numbering task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Remove any previous output
rm -f /home/ga/Documents/clinical_overview_formatted.docx
mkdir -p /home/ga/Documents

# Create the draft document using python-docx
# This ensures a clean, consistent starting state
python3 << 'PYSCRIPT'
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH
import os

doc = Document()

# Set default font to something generic
style = doc.styles['Normal']
font = style.font
font.name = 'Liberation Serif'
font.size = Pt(11)

# Remove default margins (set to 1 inch - standard default)
for section in doc.sections:
    section.top_margin = Inches(1)
    section.bottom_margin = Inches(1)
    section.left_margin = Inches(1)
    section.right_margin = Inches(1)

# ============================
# TITLE PAGE
# ============================
for _ in range(4):
    doc.add_paragraph('')

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('MODULE 2.5')
run.bold = True
run.font.size = Pt(18)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('Clinical Overview')
run.bold = True
run.font.size = Pt(16)

doc.add_paragraph('')

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('Sorvimab')
run.bold = True
run.font.size = Pt(14)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('(Anti-PD-L1 Humanized Monoclonal Antibody)')
run.font.size = Pt(12)

doc.add_paragraph('')

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('NDA 215847')
run.bold = True
run.font.size = Pt(13)

doc.add_paragraph('')
doc.add_paragraph('')

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('For the Treatment of Locally Advanced or Metastatic\nNon-Small Cell Lung Cancer (NSCLC)')
run.font.size = Pt(12)

doc.add_paragraph('')

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('Submitted by:')
run.font.size = Pt(11)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('Meridian Biotherapeutics, Inc.')
run.bold = True
run.font.size = Pt(12)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('350 Innovation Drive, Cambridge, MA 02142')
run.font.size = Pt(11)

doc.add_paragraph('')

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('January 2025')
run.font.size = Pt(11)

# ============================
# TABLE OF CONTENTS (placeholder)
# ============================
# Note: Using page break, NOT section break
doc.add_page_break()

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = p.add_run('Table of Contents')
run.bold = True
run.font.size = Pt(14)

doc.add_paragraph('')
doc.add_paragraph('Table of Contents — To be generated after final formatting is complete.')
doc.add_paragraph('')
doc.add_paragraph('')

# ============================
# EXECUTIVE SUMMARY
# ============================
p = doc.add_paragraph()
run = p.add_run('Executive Summary')
run.bold = True
run.font.size = Pt(13)

doc.add_paragraph('')

doc.add_paragraph(
    'Sorvimab is a fully humanized immunoglobulin G4 (IgG4) monoclonal antibody directed against '
    'programmed death-ligand 1 (PD-L1). By binding to PD-L1 expressed on tumor cells and tumor-infiltrating '
    'immune cells, sorvimab blocks the interaction between PD-L1 and its receptors PD-1 and B7.1 (CD80), '
    'thereby releasing PD-L1/PD-1-mediated inhibition of the anti-tumor immune response. This mechanism '
    'restores T-cell-mediated cytotoxicity against tumor cells and has demonstrated clinically meaningful '
    'efficacy in patients with advanced non-small cell lung cancer.'
)

doc.add_paragraph(
    'The clinical development program for sorvimab in NSCLC comprises three completed clinical studies '
    'enrolling a total of 1,847 patients. The pivotal Phase III trial (Study SRV-301, MERIDIAN-Lung) was '
    'a randomized, double-blind, placebo-controlled study comparing sorvimab 1200 mg intravenously every '
    '3 weeks plus platinum-based chemotherapy versus placebo plus platinum-based chemotherapy in 1,202 '
    'patients with previously untreated Stage IV NSCLC. The primary endpoint of overall survival (OS) '
    'demonstrated a statistically significant improvement with a hazard ratio of 0.71 (95% CI: 0.59–0.86; '
    'p < 0.001), corresponding to a median OS of 18.7 months versus 13.2 months in the control arm.'
)

# ============================
# 2.5.1 Product Development Rationale
# ============================
doc.add_page_break()

p = doc.add_paragraph()
run = p.add_run('2.5.1 Product Development Rationale')
run.bold = True
run.font.size = Pt(13)

doc.add_paragraph('')

doc.add_paragraph(
    'Non-small cell lung cancer accounts for approximately 85% of all lung cancer diagnoses and remains '
    'the leading cause of cancer-related mortality worldwide. Despite advances in targeted therapy for '
    'oncogene-driven tumors, the majority of NSCLC patients lack actionable driver mutations and rely on '
    'cytotoxic chemotherapy with limited survival benefit. The discovery that tumors exploit the PD-1/PD-L1 '
    'immune checkpoint axis to evade anti-tumor immunity provided a compelling therapeutic rationale for '
    'developing antibodies that block this interaction.'
)

doc.add_paragraph(
    'Sorvimab was engineered with a modified IgG4 Fc region incorporating a S228P hinge stabilization '
    'mutation to minimize Fab-arm exchange while preserving the reduced effector function characteristic '
    'of IgG4 antibodies. Preclinical studies demonstrated high-affinity binding to human PD-L1 (KD = 0.43 nM) '
    'with no detectable binding to PD-L2, confirming target specificity. In syngeneic tumor models, '
    'murine surrogate anti-PD-L1 antibody treatment produced dose-dependent tumor growth inhibition with '
    'complete responses observed at doses ≥ 5 mg/kg.'
)

# ============================
# 2.5.2 Overview of Biopharmaceutics
# ============================
p = doc.add_paragraph()
run = p.add_run('2.5.2 Overview of Biopharmaceutics')
run.bold = True
run.font.size = Pt(13)

doc.add_paragraph('')

doc.add_paragraph(
    'Sorvimab is formulated as a sterile, preservative-free, clear to slightly opalescent, colorless to '
    'slightly yellow solution for intravenous infusion at a concentration of 60 mg/mL. Each single-dose '
    'vial contains 1200 mg of sorvimab in 20 mL of solution. The formulation contains L-histidine (3.1 mg/mL), '
    'L-histidine hydrochloride monohydrate (4.0 mg/mL), trehalose dihydrate (80 mg/mL), and polysorbate 20 '
    '(0.5 mg/mL) at pH 6.0 ± 0.3.'
)

# ============================
# 2.5.3 Overview of Clinical Pharmacology
# ============================
p = doc.add_paragraph()
run = p.add_run('2.5.3 Overview of Clinical Pharmacology')
run.bold = True
run.font.size = Pt(13)

doc.add_paragraph('')

doc.add_paragraph(
    'The clinical pharmacology of sorvimab was characterized in a Phase I dose-escalation study (SRV-101) '
    'and through population pharmacokinetic (popPK) modeling integrating data from all three clinical studies. '
    'Following intravenous administration of 1200 mg every 3 weeks, sorvimab exhibited linear pharmacokinetics '
    'with a geometric mean steady-state Cmax of 412 μg/mL (CV%: 28%), AUC0-21d of 4,970 μg·day/mL (CV%: 32%), '
    'and Ctrough of 124 μg/mL (CV%: 41%).'
)

# ============================
# REFERENCES
# ============================
p = doc.add_paragraph()
run = p.add_run('References')
run.bold = True
run.font.size = Pt(13)

doc.add_paragraph('')

references = [
    'Brahmer J, Reckamp KL, Baas P, et al. Nivolumab versus docetaxel in advanced squamous-cell non-small-cell lung cancer. N Engl J Med. 2015;373(2):123-135.',
    'Borghaei H, Paz-Ares L, Horn L, et al. Nivolumab versus docetaxel in advanced nonsquamous non-small-cell lung cancer. N Engl J Med. 2015;373(17):1627-1639.',
    'Herbst RS, Baas P, Kim DW, et al. Pembrolizumab versus docetaxel for previously treated, PD-L1-positive, advanced non-small-cell lung cancer (KEYNOTE-010): a randomised controlled trial. Lancet. 2016;387(10027):1540-1550.',
    'Reck M, Rodríguez-Abreu D, Robinson AG, et al. Pembrolizumab versus chemotherapy for PD-L1-positive non-small-cell lung cancer. N Engl J Med. 2016;375(19):1823-1833.',
]

for ref in references:
    doc.add_paragraph(ref)

# Save
output_path = '/home/ga/Documents/clinical_overview_draft.docx'
os.makedirs(os.path.dirname(output_path), exist_ok=True)
doc.save(output_path)
print(f"Draft document created: {output_path}")
PYSCRIPT

# Set ownership
chown ga:ga /home/ga/Documents/clinical_overview_draft.docx

# Kill any existing LibreOffice instances
pkill -f soffice 2>/dev/null || true
sleep 2

# Launch LibreOffice Writer with the document
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer /home/ga/Documents/clinical_overview_draft.docx &"
sleep 5

# Wait for Writer window
echo "Waiting for Writer window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "clinical_overview_draft"; then
        echo "Writer window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
sleep 2
DISPLAY=:1 wmctrl -r "clinical_overview_draft" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "clinical_overview_draft" 2>/dev/null || true

# Dismiss any startup dialogs
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="