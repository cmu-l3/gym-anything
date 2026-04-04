#!/bin/bash
set -e

echo "=== Setting up format_academic_paper ==="

source /workspace/scripts/task_utils.sh

sudo -u ga mkdir -p /home/ga/Documents

python3 <<'PY'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

paragraphs = [
    "On the Origin of Species",
    "Charles Darwin",
    "",
    "Variation Under Domestication",
    (
        "Domesticated animals and cultivated plants display extraordinary variation. "
        "Breeders repeatedly observe that inherited differences accumulate when they "
        "select for useful traits over many generations."
    ),
    "Causes of Variability",
    (
        "The conditions of life appear to act in two ways: directly on the whole "
        "organization and indirectly through the reproductive system, producing "
        "heritable differences of form and habit."
    ),
    "Effects of Habit and Use",
    (
        "Use strengthens organs while disuse weakens them. Under domestication these "
        "effects can become fixed, especially when selection preserves the resulting forms."
    ),
    "Variation Under Nature",
    (
        "Natural populations vary from place to place, and these differences matter "
        "because they determine which individuals are better suited to local conditions."
    ),
    "Geometrical Ratio of Increase",
    (
        "Every species tends to increase at a geometrical ratio, yet resources remain "
        "limited. The inevitable consequence is a recurrent struggle for existence."
    ),
    "Struggle for Existence",
    (
        "Because more individuals are born than can survive, organisms compete with one "
        "another and with their environment for food, shelter, and opportunity."
    ),
    "Complex Relations of All Animals",
    (
        "No organism stands alone. Predators, competitors, parasites, and climate each "
        "shape which varieties persist and which are gradually lost."
    ),
    "Natural Selection",
    (
        "If profitable variations occur, however slight, individuals possessing them "
        "will have the best chance of surviving and of leaving offspring."
    ),
]

for text in paragraphs:
    doc.text.addElement(P(text=text))

doc.save("/home/ga/Documents/origin_of_species.odt")
PY

chown ga:ga /home/ga/Documents/origin_of_species.odt
date +%s > /tmp/format_academic_paper_start_ts

pkill -f calligrawords 2>/dev/null || true
sleep 1

su - ga -c "DISPLAY=:1 calligrawords /home/ga/Documents/origin_of_species.odt > /tmp/calligra_words.log 2>&1 &"

wait_for_window "Calligra Words" 60 || wait_for_window "origin_of_species" 30

wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$wid" || true
fi

sleep 2
take_screenshot /tmp/format_academic_paper_start.png

echo "=== Setup complete ==="
