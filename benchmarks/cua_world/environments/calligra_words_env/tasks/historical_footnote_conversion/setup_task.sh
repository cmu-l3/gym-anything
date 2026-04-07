#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Historical Footnote Conversion Task ==="

kill_calligra_processes

install -d -o ga -g ga /home/ga/Documents

rm -f /home/ga/Documents/triangle_fire_essay.odt

python3 << 'PYEOF'
import sys
try:
    from odf.opendocument import OpenDocumentText
    from odf.text import P, H
    from odf.style import Style, TextProperties, ParagraphProperties
except ImportError:
    print("Failed to import odfpy. Please ensure python3-odf is installed.")
    sys.exit(1)

doc = OpenDocumentText()

# Define styles
title_style = Style(name="Title", family="paragraph")
title_style.addElement(TextProperties(fontsize="18pt", fontweight="bold"))
title_style.addElement(ParagraphProperties(textalign="center"))
doc.styles.addElement(title_style)

h1_style = Style(name="Heading1", family="paragraph")
h1_style.addElement(TextProperties(fontsize="14pt", fontweight="bold"))
h1_style.addElement(ParagraphProperties(margintop="0.4cm", marginbottom="0.2cm"))
doc.styles.addElement(h1_style)

body_style = Style(name="BodyText", family="paragraph")
body_style.addElement(ParagraphProperties(textalign="justify", marginbottom="0.2cm"))
doc.styles.addElement(body_style)

doc.text.addElement(P(stylename=title_style, text="The Triangle Shirtwaist Factory Fire: Industrial Reform Through Tragedy"))
doc.text.addElement(P(stylename=body_style, text=""))

doc.text.addElement(H(outlinelevel=1, stylename=h1_style, text="The Fire and Its Immediate Aftermath"))
doc.text.addElement(P(stylename=body_style, text="On March 25, 1911, a fire broke out on the eighth floor of the Asch Building at Washington Place, where the Triangle Shirtwaist Company employed over 500 workers [1]. The mostly young, immigrant women found themselves trapped when they tried to escape."))
doc.text.addElement(P(stylename=body_style, text="Managers had locked the stairwell doors [2] to prevent theft and unauthorized breaks, a common but deadly practice. As the flames spread rapidly, panic ensued."))
doc.text.addElement(P(stylename=body_style, text="By the time the fire was extinguished, 146 garment workers perished [3]. Many jumped from the windows to the pavement below because the building's single, inadequate fire escape collapsed [4] under the weight of the fleeing workers."))

doc.text.addElement(H(outlinelevel=1, stylename=h1_style, text="Legacy and Legislative Impact"))
doc.text.addElement(P(stylename=body_style, text="The tragedy provoked widespread outrage. Despite the public anger, the factory owners were acquitted of manslaughter charges [5], highlighting the inadequacy of existing labor laws."))
doc.text.addElement(P(stylename=body_style, text="However, the fire galvanized the labor movement [6], swelling the ranks of the International Ladies' Garment Workers' Union and sparking demands for workplace safety reform."))
doc.text.addElement(P(stylename=body_style, text="In response, the New York State legislature established the Factory Investigating Commission [7]. Frances Perkins, who witnessed the fire, played a crucial role in these investigations and later became Secretary of Labor, integrating these lessons into the New Deal."))
doc.text.addElement(P(stylename=body_style, text="The Commission's findings led to comprehensive new laws, including the Sullivan-Hoey Fire Prevention Law, which became the foundation for modern workplace safety standards [8] across the United States."))

doc.text.addElement(H(outlinelevel=1, stylename=h1_style, text="References"))
doc.text.addElement(P(stylename=body_style, text="Von Drehle, David. Triangle: The Fire That Changed America. Atlantic Monthly Press, 2003, pp. 2–3."))
doc.text.addElement(P(stylename=body_style, text="Stein, Leon. The Triangle Fire. Cornell University Press, 1962, pp. 24–26."))
doc.text.addElement(P(stylename=body_style, text='\"141 Men and Girls Die in Waist Factory Fire.\" New York Times, 26 March 1911, p. 1.'))
doc.text.addElement(P(stylename=body_style, text="Report of the Factory Investigating Commission, State of New York. Preliminary Report, vol. 1, 1912, pp. 18–20."))
doc.text.addElement(P(stylename=body_style, text='McEvoy, Arthur F. \"The Triangle Shirtwaist Factory Fire of 1911: Social Change, Industrial Accidents, and the Evolution of Common-Sense Causality.\" Law & Social Inquiry, vol. 20, no. 2, 1995, pp. 621–649.'))
doc.text.addElement(P(stylename=body_style, text="Greenwald, Richard A. The Triangle Fire, the Protocols of Peace, and Industrial Democracy in Progressive Era New York. Temple University Press, 2005, pp. 1–8."))
doc.text.addElement(P(stylename=body_style, text="Argersinger, Jo Ann E. The Triangle Fire: A Brief History with Documents. Bedford/St. Martin's, 2009, pp. 45–52."))
doc.text.addElement(P(stylename=body_style, text='Kheel Center, Cornell University ILR School. \"The 1911 Triangle Factory Fire.\" Online exhibit, accessed 2024.'))

doc.save("/home/ga/Documents/triangle_fire_essay.odt")
PYEOF

chown ga:ga /home/ga/Documents/triangle_fire_essay.odt

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Launch Calligra Words with the document
launch_calligra_document "/home/ga/Documents/triangle_fire_essay.odt"

# Wait for window
wait_for_window "triangle_fire_essay" 15
sleep 2

WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize window (CRITICAL for agent visibility)
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    # Dismiss any default popups/dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
fi

take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="