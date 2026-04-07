#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Academic Journal Typesetting Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

kill_calligra_processes

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

rm -f /home/ga/Documents/crispr_brassica_manuscript.odt
rm -f /home/ga/Desktop/journal_style_guide.txt

# ------------------------------------------------------------------
# Create the journal style guide on the Desktop
# ------------------------------------------------------------------
cat > /home/ga/Desktop/journal_style_guide.txt << 'EOF'
Journal of Plant Genomics - Pre-print Style Guide

Authors submitting manuscripts must format their documents according to the following typographical rules before peer-review routing:

1. Title & Authors: 
   - The manuscript title must be Centered, Bold, and at least 16pt font size.
   - The authors line and affiliation line must be Centered below the title.

2. Abstract Formatting: 
   - The abstract paragraph must stand out from the body text. Apply a Block Indent (indent BOTH the Left and Right margins by at least 0.5 inches / 1.25 cm).
   - The entire text of the abstract must be Italicized.

3. Headings:
   - Primary sections (Abstract, Introduction, Materials and Methods, Results, Discussion, Acknowledgments, References) must be formatted using the "Heading 1" style.
   - Secondary methodological/result subsections must be formatted using the "Heading 2" style.

4. Body Text: 
   - All standard narrative paragraphs must have Justified alignment.

5. Bibliography / References: 
   - The reference list MUST be formatted with a Hanging Indent so the numbers hang to the left of the text block. 
   - (e.g., The paragraph's Left margin must be indented positively, and its First-line indent must be indented negatively by an equal amount).
EOF
chown ga:ga /home/ga/Desktop/journal_style_guide.txt

# ------------------------------------------------------------------
# Create the unformatted manuscript using odfpy
# ALL content is plain P elements — no heading styles, no bold, etc.
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# ── Title and Authors ──
add_paragraph("High-efficiency CRISPR-Cas9 multiplex gene editing in Brassica napus")
add_paragraph("J. Smith, A. Doe, M. Wang")
add_paragraph("Department of Plant Genomics, University of Science")
add_paragraph("")

# ── Abstract ──
add_paragraph("Abstract")
add_paragraph(
    "Brassica napus (rapeseed) is an important oilseed crop globally, but its "
    "allotetraploid genome complicates traditional breeding and mutagenesis "
    "efforts. Here, we present a high-efficiency multiplex CRISPR-Cas9 system "
    "optimized specifically for B. napus. By utilizing an endogenous tRNA-processing "
    "system, we successfully targeted four independent genomic loci simultaneously "
    "with editing efficiencies exceeding 85% in the T0 generation. Our optimized "
    "constructs significantly reduce off-target effects while maintaining robust "
    "on-target indel mutation rates. This system provides a powerful platform for "
    "accelerating functional genomics and agronomical trait improvement in Brassica species."
)
add_paragraph("")

# ── Introduction ──
add_paragraph("Introduction")
add_paragraph(
    "Targeted genome editing using the CRISPR-Cas9 system has revolutionized "
    "plant biology and crop improvement. However, multiplex gene editing in "
    "polyploid crops like Brassica napus remains challenging due to the presence "
    "of multiple homoeologous gene copies. Traditional single-sgRNA expression "
    "cassettes are inefficient for knocking out entire gene families..."
)
add_paragraph("")

# ── Materials and Methods ──
add_paragraph("Materials and Methods")

add_paragraph("Plant material and growth conditions")
add_paragraph(
    "Brassica napus cultivar Westar was used for all experiments. Seeds were "
    "surface-sterilized and germinated on MS medium. Seedlings were grown in "
    "a controlled environmental chamber at 22°C under a 16-h light / 8-h dark "
    "photoperiod with a light intensity of 150 μmol m−2 s−1."
)

add_paragraph("Vector construction")
add_paragraph(
    "The multiplex sgRNA cassettes were assembled using the Golden Gate cloning "
    "method. The polycistronic tRNA-gRNA architecture was synthesized and cloned "
    "into the pRGEB32-Bn binary vector containing a plant-codon optimized Cas9 "
    "driven by the CaMV 35S promoter."
)
add_paragraph("")

# ── Results ──
add_paragraph("Results")

add_paragraph("Validation of sgRNA efficiency")
add_paragraph(
    "We designed four sgRNAs targeting the ALCATRAZ gene homoeologs. Protoplast "
    "transfection assays revealed high cleavage activities for all four guides. "
    "Subsequent Agrobacterium-mediated transformation yielded 142 independent "
    "transgenic lines. Deep sequencing of the target loci confirmed that 121 "
    "lines (85.2%) harbored mutations at three or more targeted sites."
)
add_paragraph("")

# ── Discussion ──
add_paragraph("Discussion")
add_paragraph(
    "Our results demonstrate that the optimized multiplex CRISPR-Cas9 system "
    "is highly effective for complex genome editing in Brassica napus. The "
    "high multiplexing capability enables the simultaneous knockout of redundant "
    "gene families, bypassing the genetic buffering effects typically observed "
    "in polyploid species."
)
add_paragraph("")

# ── Acknowledgments ──
add_paragraph("Acknowledgments")
add_paragraph("This work was supported by the National Plant Science Foundation (Grant No. 123456).")
add_paragraph("")

# ── References ──
add_paragraph("References")
add_paragraph(
    "1. Cong L., Ran F. A., Cox D., Lin S., Barretto R., Habib N., ... & Zhang F. "
    "(2013). Multiplex genome engineering using CRISPR/Cas systems. Science, 339(6121), 819-823."
)
add_paragraph(
    "2. Jinek M., Chylinski K., Fonfara I., Hauer M., Doudna J. A., & Charpentier E. "
    "(2012). A programmable dual-RNA-guided DNA endonuclease in adaptive bacterial "
    "immunity. Science, 337(6096), 816-821."
)
add_paragraph(
    "3. Mao Y., Zhang H., Xu N., Zhang B., Gou F., & Zhu J. K. (2013). Application "
    "of the CRISPR-Cas system for efficient genome engineering in plants. "
    "Molecular Plant, 6(6), 2008-2011."
)

doc.save("/home/ga/Documents/crispr_brassica_manuscript.odt")
PYEOF
chown ga:ga /home/ga/Documents/crispr_brassica_manuscript.odt

# Launch Calligra Words with the document
echo "Launching Calligra Words..."
launch_calligra_document "/home/ga/Documents/crispr_brassica_manuscript.odt"

# Wait for Calligra to load and maximize
wait_for_window "Calligra Words" 30
sleep 3
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    # Dismiss potential startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task Setup Complete ==="