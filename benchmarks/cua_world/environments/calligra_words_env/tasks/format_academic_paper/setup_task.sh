#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Format Academic Paper Task ==="

install -d -o ga -g ga /home/ga/Documents
kill_calligra_processes
rm -f /home/ga/Documents/origin_of_species.odt

python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()


def add_paragraph(text=""):
    doc.text.addElement(P(text=text))


add_paragraph("On the Origin of Species")
add_paragraph("Charles Darwin")
add_paragraph("")
add_paragraph("Variation Under Domestication")
add_paragraph("Causes of Variability")
add_paragraph(
    "When we compare the individuals of the same variety or sub-variety of our older "
    "cultivated plants and animals, one of the first points which strikes us is, that "
    "they generally differ much more from each other than do the individuals of any one "
    "species or variety in a state of nature. We are driven to conclude that this great "
    "variability is due to our domestic productions having been raised under conditions "
    "of life not so uniform as those to which the parent species had been exposed."
)
add_paragraph("Effects of Habit and Use")
add_paragraph(
    "Changed habits produce an inherited effect, as in the period of the flowering of "
    "plants when transported from one climate to another. With animals the increased use "
    "or disuse of parts has had a marked influence; thus the domestic duck flies less and "
    "walks more than its wild parent, and the bones of the wing weigh less while those of "
    "the leg weigh more in proportion to the whole skeleton."
)
add_paragraph("")
add_paragraph("Variation Under Nature")
add_paragraph(
    "No one supposes that all the individuals of the same species are cast in the same "
    "actual mould. These individual differences are of the highest importance for us, for "
    "they are often inherited, and they thus afford materials for natural selection to "
    "act on and accumulate."
)
add_paragraph("")
add_paragraph("Struggle for Existence")
add_paragraph("Geometrical Ratio of Increase")
add_paragraph(
    "A struggle for existence inevitably follows from the high rate at which all organic "
    "beings tend to increase. Every being which during its natural lifetime produces "
    "several eggs or seeds must suffer destruction during some period of its life, and "
    "during some season or occasional year, otherwise, on the principle of geometrical "
    "increase, its numbers would quickly become so inordinately great that no country "
    "could support the product."
)
add_paragraph("Complex Relations of All Animals")
add_paragraph(
    "The relations of all animals and plants throughout nature are the fullest sense "
    "complex. A plant on the edge of a desert is said to struggle for life against the "
    "drought, though more properly it should be said to be dependent on moisture; and a "
    "plant in the midst of its range has to contend with many rivals, enemies, and hidden "
    "checks before it can increase in numbers."
)
add_paragraph("")
add_paragraph("Natural Selection")
add_paragraph(
    "Natural selection acts only by taking advantage of slight successive variations; "
    "she can never take a leap, but must advance by the shortest and slowest steps. If "
    "variations useful to any organic being do occur, assuredly individuals thus "
    "characterised will have the best chance of being preserved in the struggle for life, "
    "and from the strong principle of inheritance they will tend to produce offspring "
    "similarly characterised."
)

doc.save("/home/ga/Documents/origin_of_species.odt", False)
print("Created origin_of_species.odt")
PYEOF

chown ga:ga /home/ga/Documents/origin_of_species.odt
chmod 0664 /home/ga/Documents/origin_of_species.odt

echo "Launching Calligra Words..."
launch_calligra_document "/home/ga/Documents/origin_of_species.odt" "/tmp/calligra_words_task.log"

if ! wait_for_process "/usr/bin/calligrawords" 20; then
    wait_for_process "calligrawords" 15 || true
fi

if ! wait_for_window "Calligra Words\\|origin_of_species" 60; then
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

take_screenshot /tmp/calligra_format_academic_paper_setup.png

echo "=== Format Academic Paper Task Setup Complete ==="
