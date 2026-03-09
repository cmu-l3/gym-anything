#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome PDF Viewer Navigation and Search Task Setup ==="
echo "Task: Open PDF, search for 'hypothesis', navigate to 3rd occurrence on page 7"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip wkhtmltopdf || true

# Install PDF generation libraries
pip3 install -q reportlab pypdf pillow 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create the multi-page PDF document with searchable text
echo "Creating sample research PDF document..."
PDF_DIR="/home/ga/Documents"
mkdir -p "$PDF_DIR"

# Create PDF using Python reportlab
python3 << 'PYPDF'
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, PageBreak
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY
import os

# PDF output path
pdf_path = "/home/ga/Documents/research_methodology.pdf"

# Create PDF document
doc = SimpleDocTemplate(pdf_path, pagesize=letter,
                        rightMargin=72, leftMargin=72,
                        topMargin=72, bottomMargin=18)

# Container for elements
elements = []

# Define styles
styles = getSampleStyleSheet()
title_style = ParagraphStyle(
    'CustomTitle',
    parent=styles['Heading1'],
    fontSize=24,
    textColor='#2c3e50',
    spaceAfter=30,
    alignment=TA_CENTER
)
heading_style = styles['Heading2']
normal_style = styles['BodyText']

# Page 1: Title and Introduction
elements.append(Paragraph("Research Methodology in Cognitive Science", title_style))
elements.append(Spacer(1, 0.3*inch))

elements.append(Paragraph("Chapter 1: Introduction to Research Design", heading_style))
elements.append(Spacer(1, 0.2*inch))

intro_text = """
Research methodology forms the backbone of scientific inquiry in cognitive science. 
This document explores various approaches to conducting rigorous research, from 
formulating research questions to analyzing complex datasets. Understanding proper 
methodology is essential for any researcher seeking to contribute meaningful insights 
to the field of cognitive psychology and neuroscience.
"""
elements.append(Paragraph(intro_text, normal_style))
elements.append(Spacer(1, 0.2*inch))

elements.append(Paragraph("The scientific method begins with observation and curiosity. " +
                         "Researchers must carefully design studies that can test their ideas " +
                         "while controlling for confounding variables. This requires a deep " +
                         "understanding of both theoretical frameworks and practical constraints.", normal_style))

elements.append(PageBreak())

# Page 2: Research Questions
elements.append(Paragraph("Chapter 2: Formulating Research Questions", heading_style))
elements.append(Spacer(1, 0.2*inch))

page2_text = """
A well-formulated research question guides the entire research process. It should be 
specific, measurable, and grounded in existing literature. Good research questions 
often emerge from gaps in current knowledge or inconsistencies in previous findings. 
The process of refining a research question involves extensive literature review and 
consultation with colleagues and mentors.
"""
elements.append(Paragraph(page2_text, normal_style))
elements.append(Spacer(1, 0.2*inch))

elements.append(Paragraph("Researchers must consider the scope of their investigation. " +
                         "Questions that are too broad may be impossible to answer conclusively, " +
                         "while overly narrow questions may lack theoretical significance. " +
                         "Finding the right balance is a skill developed through experience " +
                         "and critical thinking.", normal_style))

elements.append(PageBreak())

# Page 3: Literature Review (FIRST "hypothesis" mention)
elements.append(Paragraph("Chapter 3: Conducting Literature Reviews", heading_style))
elements.append(Spacer(1, 0.2*inch))

page3_text = """
The literature review serves multiple purposes in the research process. It establishes 
the theoretical foundation for your study, identifies gaps in existing knowledge, and 
helps refine your research hypothesis. A comprehensive review requires systematic 
searching of academic databases, careful reading of relevant papers, and critical 
evaluation of methodologies and findings.
"""
elements.append(Paragraph(page3_text, normal_style))
elements.append(Spacer(1, 0.2*inch))

elements.append(Paragraph("When reviewing literature, pay attention to both supporting and " +
                         "contradictory evidence. Understanding alternative explanations strengthens " +
                         "your own theoretical framework. Document all sources carefully to facilitate " +
                         "proper citation and allow others to trace your intellectual lineage.", normal_style))

elements.append(PageBreak())

# Page 4: Study Design
elements.append(Paragraph("Chapter 4: Experimental Design Principles", heading_style))
elements.append(Spacer(1, 0.2*inch))

page4_text = """
Experimental design determines the validity and reliability of your findings. Key 
considerations include sample size calculation, randomization procedures, control 
conditions, and measurement instruments. Between-subjects and within-subjects designs 
each have advantages and limitations that must be carefully weighed against your 
research objectives and practical constraints.
"""
elements.append(Paragraph(page4_text, normal_style))
elements.append(Spacer(1, 0.2*inch))

elements.append(Paragraph("Pilot studies are invaluable for identifying potential problems " +
                         "before committing to a full-scale investigation. They allow you to " +
                         "test procedures, refine instructions, and estimate effect sizes for " +
                         "power analysis. Never underestimate the importance of thorough preparation.", normal_style))

elements.append(PageBreak())

# Page 5: Variables and Measures (SECOND "hypothesis" mention)
elements.append(Paragraph("Chapter 5: Variables and Measurement", heading_style))
elements.append(Spacer(1, 0.2*inch))

page5_text = """
Operational definitions translate abstract concepts into measurable variables. 
Independent variables are manipulated by the researcher, while dependent variables 
reflect the outcomes of interest. Careful operationalization ensures that your 
measurements actually capture the constructs specified in your hypothesis. Poor 
measurement invalidates even the most elegant theoretical framework.
"""
elements.append(Paragraph(page5_text, normal_style))
elements.append(Spacer(1, 0.2*inch))

elements.append(Paragraph("Reliability and validity are fundamental psychometric properties. " +
                         "Reliability refers to consistency of measurement across time and conditions. " +
                         "Validity concerns whether you are measuring what you intend to measure. " +
                         "Multiple measurement approaches can provide convergent evidence.", normal_style))

elements.append(PageBreak())

# Page 6: Data Collection
elements.append(Paragraph("Chapter 6: Data Collection Procedures", heading_style))
elements.append(Spacer(1, 0.2*inch))

page6_text = """
Systematic data collection requires detailed protocols and trained personnel. 
Standardization minimizes variability due to procedural differences. Document 
all aspects of the data collection process, including any deviations from the 
original plan. Unanticipated problems are common, and transparency about challenges 
encountered strengthens rather than weakens your research.
"""
elements.append(Paragraph(page6_text, normal_style))
elements.append(Spacer(1, 0.2*inch))

elements.append(Paragraph("Ethical considerations must guide every aspect of data collection. " +
                         "Informed consent, confidentiality, and the right to withdraw are fundamental " +
                         "principles. Institutional review boards provide oversight to ensure participant " +
                         "welfare and scientific integrity.", normal_style))

elements.append(PageBreak())

# Page 7: Statistical Analysis (THIRD "hypothesis" mention - TARGET)
elements.append(Paragraph("Chapter 7: Statistical Analysis and Inference", heading_style))
elements.append(Spacer(1, 0.2*inch))

page7_text = """
Statistical analysis transforms raw data into meaningful conclusions. The choice of 
statistical tests depends on your research design, data characteristics, and the 
specific hypothesis being tested. Parametric tests assume normally distributed data, 
while non-parametric alternatives are more robust to violations of assumptions. 
Understanding the logic behind statistical procedures is more important than 
mechanical application of formulas.
"""
elements.append(Paragraph(page7_text, normal_style))
elements.append(Spacer(1, 0.2*inch))

elements.append(Paragraph("Effect sizes provide crucial information beyond p-values. They quantify " +
                         "the magnitude of observed differences or relationships, allowing readers to " +
                         "judge practical significance. Confidence intervals convey the precision of " +
                         "estimates and acknowledge inherent uncertainty in statistical inference.", normal_style))

elements.append(PageBreak())

# Page 8: Interpretation (FOURTH "hypothesis" mention)
elements.append(Paragraph("Chapter 8: Interpreting Results", heading_style))
elements.append(Spacer(1, 0.2*inch))

page8_text = """
Interpretation requires careful reasoning about what the data can and cannot tell us. 
Statistically significant results support or fail to support your hypothesis, but they 
do not prove or disprove theoretical claims in any absolute sense. Alternative 
explanations must be considered and addressed. The strongest conclusions emerge when 
multiple lines of evidence converge on a consistent interpretation.
"""
elements.append(Paragraph(page8_text, normal_style))
elements.append(Spacer(1, 0.2*inch))

elements.append(Paragraph("Null results are often as informative as significant findings. They may " +
                         "indicate that an effect does not exist, that it is smaller than your study " +
                         "could detect, or that methodological problems obscured a real effect. " +
                         "Careful analysis of statistical power helps distinguish these possibilities.", normal_style))

elements.append(PageBreak())

# Page 9: Writing and Publishing (FIFTH "hypothesis" mention)
elements.append(Paragraph("Chapter 9: Scientific Writing and Publication", heading_style))
elements.append(Spacer(1, 0.2*inch))

page9_text = """
Clear scientific writing communicates your research to the broader community. The 
standard IMRaD structure (Introduction, Methods, Results, Discussion) provides a 
logical framework. The introduction motivates the research and states your hypothesis. 
Methods must be detailed enough for replication. Results present findings objectively, 
while the discussion interprets significance and acknowledges limitations.
"""
elements.append(Paragraph(page9_text, normal_style))
elements.append(Spacer(1, 0.2*inch))

elements.append(Paragraph("Peer review improves research quality through critical evaluation by experts. " +
                         "Reviewers assess methodology, statistical analysis, and interpretation. Responding " +
                         "constructively to reviewer feedback strengthens your manuscript. The revision process, " +
                         "while sometimes frustrating, ultimately produces better science.", normal_style))

elements.append(PageBreak())

# Page 10: Conclusion
elements.append(Paragraph("Chapter 10: Conclusion and Future Directions", heading_style))
elements.append(Spacer(1, 0.2*inch))

page10_text = """
Rigorous research methodology is essential for advancing cognitive science. This guide 
has covered fundamental principles from research design through publication. However, 
methodology continues to evolve with new technologies and analytical techniques. 
Researchers must remain lifelong learners, updating their skills to leverage emerging 
tools while maintaining core scientific values of transparency, rigor, and integrity.
"""
elements.append(Paragraph(page10_text, normal_style))
elements.append(Spacer(1, 0.2*inch))

elements.append(Paragraph("Future research will increasingly incorporate computational modeling, " +
                         "big data analytics, and interdisciplinary collaboration. These advances " +
                         "create exciting opportunities while raising new methodological challenges. " +
                         "By maintaining strong foundations in research design and critical thinking, " +
                         "cognitive scientists can navigate this evolving landscape successfully.", normal_style))

# Build PDF
doc.build(elements)

print(f"✓ PDF created successfully at {pdf_path}")

PYPDF

# Set ownership
chown ga:ga "$PDF_DIR/research_methodology.pdf"
echo "✓ PDF document created: $PDF_DIR/research_methodology.pdf"

# Verify PDF was created
if [ -f "$PDF_DIR/research_methodology.pdf" ]; then
    PDF_SIZE=$(stat -f%z "$PDF_DIR/research_methodology.pdf" 2>/dev/null || stat -c%s "$PDF_DIR/research_methodology.pdf" 2>/dev/null || echo "0")
    echo "✓ PDF file size: $PDF_SIZE bytes"
else
    echo "⚠ Warning: PDF file was not created successfully"
fi

# Ensure Chrome is properly focused and ready
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh about:blank" &
    sleep 5
else
    echo "Chrome is already running"
fi

# Wait for Chrome to be fully ready
sleep 2

# IMPORTANT: Click at center to select desktop (multi-desktop environments)
# This ensures we're on the first desktop where Chrome is running
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Chrome window using wmctrl
export DISPLAY=:1
wid=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | head -1 | awk '{print $1}')
if [ -z "$wid" ]; then
    echo "Warning: Could not find Chrome window"
else
    echo "Focusing Chrome window: $wid"
    wmctrl -i -a $wid || true
    sleep 1
fi

# Open the PDF in Chrome
PDF_PATH="file:///home/ga/Documents/research_methodology.pdf"
echo "Opening PDF in Chrome: $PDF_PATH"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 '$PDF_PATH'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 4

# Wait for PDF to load
echo "Waiting for PDF to load..."
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""')
    echo "✓ Active URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "PDF should be open in Chrome's built-in viewer"
echo "Agent should:"
echo "  1. Press Ctrl+F to open search"
echo "  2. Type 'hypothesis' in search box"
echo "  3. Click 'Next' to navigate to 3rd occurrence"
echo "  4. Verify it lands on page 7"