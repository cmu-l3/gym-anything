#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Bibliography Formatting Task ==="

# Clean up any prior states
kill_calligra_processes
install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop
rm -f /home/ga/Documents/vaccine_hesitancy_brief.odt
rm -f /home/ga/Desktop/apa_references_guide.txt
rm -f /tmp/task_start_time.txt
rm -f /tmp/task_result.json

# Record start time
date +%s > /tmp/task_start_time.txt

# Create APA reference guide
cat > /home/ga/Desktop/apa_references_guide.txt << 'EOF'
APA 7th Edition Reference List Formatting Summary:

1. Heading: The word "References" should be a Level 1 Heading, centered or left-aligned at the top of the section.
2. Alphabetical Order: All entries must be ordered alphabetically by the last name of the first author.
3. Indentation: Apply a hanging indent to each reference list entry. The first line of the reference is flush left, and subsequent lines are indented (typically 0.5 inches or 1.27 cm).
4. Typography: Use a consistent font and size throughout the document (e.g., 12pt standard serif or sans-serif).
5. Italics: Italicize titles of journals, magazines, newspapers, and books. Do NOT italicize the titles of journal articles.
EOF
chown ga:ga /home/ga/Desktop/apa_references_guide.txt

# Create the ODT document with injected errors using python3 and odfpy
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.style import Style, TextProperties, ParagraphProperties
from odf.text import P, H

doc = OpenDocumentText()

# Define automatic styles
body_style = Style(name="BodyText", family="paragraph")
body_style.addElement(ParagraphProperties(textalign="justify", marginbottom="0.2cm"))
body_style.addElement(TextProperties(fontsize="12pt", fontname="Liberation Serif"))
doc.automaticstyles.addElement(body_style)

h1_style = Style(name="Heading1", family="paragraph", parentstylename="Heading_20_1")
h1_style.addElement(TextProperties(fontsize="18pt", fontweight="bold", fontname="Liberation Sans"))
h1_style.addElement(ParagraphProperties(margintop="0.4cm", marginbottom="0.2cm"))
doc.automaticstyles.addElement(h1_style)

# Error styles for references
ref_standard = Style(name="RefStandard", family="paragraph")
ref_standard.addElement(ParagraphProperties(textalign="left", marginbottom="0.2cm"))
ref_standard.addElement(TextProperties(fontsize="12pt", fontname="Liberation Serif"))
doc.automaticstyles.addElement(ref_standard)

ref_courier = Style(name="RefCourier", family="paragraph")
ref_courier.addElement(ParagraphProperties(textalign="left", marginbottom="0.2cm"))
ref_courier.addElement(TextProperties(fontsize="12pt", fontname="Courier New"))
doc.automaticstyles.addElement(ref_courier)

ref_10pt = Style(name="Ref10pt", family="paragraph")
ref_10pt.addElement(ParagraphProperties(textalign="left", marginbottom="0.2cm"))
ref_10pt.addElement(TextProperties(fontsize="10pt", fontname="Liberation Serif"))
doc.automaticstyles.addElement(ref_10pt)

def add_heading(text):
    doc.text.addElement(H(outlinelevel=1, stylename=h1_style, text=text))

def add_body(text):
    doc.text.addElement(P(stylename=body_style, text=text))

def add_ref(text, style):
    doc.text.addElement(P(stylename=style, text=text))

# Add Policy Brief Body
add_heading("Policy Brief: Addressing Vaccine Hesitancy")
add_body("Vaccine hesitancy has been identified by the World Health Organization as one of the top ten threats to global health. Despite the proven safety and efficacy of routine immunizations, a growing segment of the population exhibits reluctance or refusal to vaccinate themselves or their children.")
add_body("Understanding the psychological, social, and political roots of this hesitancy is crucial for developing effective communication strategies. The \"5C\" model—confidence, complacency, constraints, calculation, and collective responsibility—provides a robust theoretical framework for assessing these attitudes.")
add_body("To combat misinformation and build trust, public health interventions must be tailored to specific community concerns, leveraging both traditional community engagement and digital health communication platforms.")
add_body("")

# Add References Section - Intentionally plain text (not a heading)
add_ref("References", ref_standard)

# Add scrambled references with formatting errors
refs = [
    # 1. Scrambled to pos 1 (Salmon)
    ("Salmon, D. A., et al. (2015). Vaccine hesitancy: Causes, consequences, and a call to action. Vaccine, 33(Suppl 4), D66-D71.", ref_standard),
    # 2. Scrambled to pos 2 (Larson)
    ("Larson, H. J., et al. (2014). Understanding vaccine hesitancy around vaccines and vaccination from a global perspective. Vaccine, 32(19), 2150-2159.", ref_standard),
    # 3. Benin
    ("Benin, A. L., et al. (2006). Qualitative analysis of mothers' decision-making about vaccines for infants. Pediatrics, 117(5), 1532-1541.", ref_standard),
    # 4. Betsch
    ("Betsch, C., et al. (2018). Beyond confidence: Development of a measure assessing the 5C psychological antecedents of vaccination. PLOS ONE, 13(12), e0208601.", ref_standard),
    # 5. Scrambled to pos 5 (World Health Organization)
    ("World Health Organization. (2019). Ten threats to global health in 2019. WHO.", ref_standard),
    # 6. Goldstein
    ("Goldstein, S., MacDonald, N. E., & Guirguis, S. (2015). Health communication and vaccine hesitancy. Vaccine, 33(34), 4212-4214.", ref_standard),
    # 7. Dubé - Wrong font (Courier)
    ("Dubé, E., et al. (2013). Vaccine hesitancy: An overview. Human Vaccines & Immunotherapeutics, 9(8), 1763-1773.", ref_courier),
    # 8. Hornsey - Wrong size (10pt)
    ("Hornsey, M. J., Harris, E. A., & Fielding, K. S. (2018). The psychological roots of anti-vaccination attitudes. Health Psychology, 37(4), 307-315.", ref_10pt),
    # 9. Jacobson
    ("Jacobson, R. M., St. Sauver, J. L., & Finney Rutten, L. J. (2015). Vaccine hesitancy. Mayo Clinic Proceedings, 90(11), 1562-1568.", ref_standard),
    # 10. Kata - Wrong font (Courier)
    ("Kata, A. (2012). Anti-vaccine activists, Web 2.0, and the postmodern paradigm. Vaccine, 30(25), 3778-3789.", ref_courier),
    # 11. MacDonald
    ("MacDonald, N. E. (2015). Vaccine hesitancy: Definition, scope and determinants. Vaccine, 33(34), 4161-4164.", ref_standard),
    # 12. Omer
    ("Omer, S. B., et al. (2009). Vaccine refusal, mandatory immunization, and the risks of vaccine-preventable diseases. New England Journal of Medicine, 360(19), 1981-1988.", ref_standard),
    # 13. Schmid
    ("Schmid, P., et al. (2017). Barriers of influenza vaccination intention and behavior. PLOS ONE, 12(1), e0170550.", ref_standard),
    # 14. Peretti-Watel - Wrong size (10pt)
    ("Peretti-Watel, P., et al. (2015). Vaccine hesitancy: Clarifying a theoretical framework. PLOS Currents, 7.", ref_10pt),
    # 15. Roozenbeek - Wrong font (Courier)
    ("Roozenbeek, J., et al. (2020). Susceptibility to misinformation about COVID-19 around the world. Royal Society Open Science, 7(10), 201199.", ref_courier)
]

for text, style in refs:
    add_ref(text, style)

doc.save("/home/ga/Documents/vaccine_hesitancy_brief.odt")
PYEOF

chown ga:ga /home/ga/Documents/vaccine_hesitancy_brief.odt

# Launch Calligra Words directly into the document
echo "Launching Calligra Words..."
launch_calligra_document "/home/ga/Documents/vaccine_hesitancy_brief.odt"
sleep 5

# Ensure maximized and focused
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot showing start state
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="