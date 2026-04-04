#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Table of Contents Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create the document with real text from Darwin's "On the Origin of Species"
# Source: Project Gutenberg (public domain)
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt

doc = Document()

# All text is in Normal style - the agent must apply heading styles

# --- CHAPTER I ---
doc.add_paragraph("CHAPTER I. VARIATION UNDER DOMESTICATION")
doc.add_paragraph("")

doc.add_paragraph("Causes of Variability")
doc.add_paragraph("")
doc.add_paragraph(
    "When we compare the individuals of the same variety or sub-variety of our older "
    "cultivated plants and animals, one of the first points which strikes us is, that "
    "they generally differ more from each other than do the individuals of any one "
    "species or variety in a state of nature. And if we reflect on the vast diversity "
    "of the plants and animals which have been cultivated, and which have varied during "
    "all ages under the most different climates and treatment, we are driven to conclude "
    "that this great variability is due to our domestic productions having been raised "
    "under conditions of life not so uniform as, and somewhat different from, those to "
    "which the parent species had been exposed under nature."
)
doc.add_paragraph("")

doc.add_paragraph("Effects of Habit and of the Use or Disuse of Parts")
doc.add_paragraph("")
doc.add_paragraph(
    "Changed habits produce an inherited effect, as in the period of the flowering of "
    "plants when transported from one climate to another. With animals the increased use "
    "or disuse of parts has had a more marked influence; thus I find in the domestic duck "
    "that the bones of the wing weigh less and the bones of the leg more, in proportion "
    "to the whole skeleton, than do the same bones in the wild-duck; and this change may "
    "be safely attributed to the domestic duck flying much less, and walking more, than "
    "its wild parents."
)
doc.add_paragraph("")

# --- CHAPTER II ---
doc.add_paragraph("CHAPTER II. VARIATION UNDER NATURE")
doc.add_paragraph("")

doc.add_paragraph("Individual Differences")
doc.add_paragraph("")
doc.add_paragraph(
    "The many slight differences which appear in the offspring from the same parents, or "
    "which it may be presumed have thus arisen, from being observed in the individuals of "
    "the same species inhabiting the same confined locality, may be called individual "
    "differences. No one supposes that all the individuals of the same species are cast "
    "in the same actual mould. These individual differences are of the highest importance "
    "for us, for they are often inherited, as must be familiar to every one; and they "
    "thus afford materials for natural selection to act on and accumulate."
)
doc.add_paragraph("")

doc.add_paragraph("Doubtful Species")
doc.add_paragraph("")
doc.add_paragraph(
    "The forms which possess in some considerable degree the character of species, but "
    "which are so closely similar to other forms, or are so closely linked to them by "
    "intermediate gradations, that naturalists do not like to rank them as distinct "
    "species, are in several respects the most important for us. We have every reason "
    "to believe that many of these doubtful and closely allied forms have permanently "
    "retained their characters for a long time."
)
doc.add_paragraph("")

# --- CHAPTER III ---
doc.add_paragraph("CHAPTER III. STRUGGLE FOR EXISTENCE")
doc.add_paragraph("")

doc.add_paragraph("The Term, Struggle for Existence")
doc.add_paragraph("")
doc.add_paragraph(
    "I should premise that I use this term in a large and metaphorical sense, including "
    "dependence of one being on another, and including (which is more important) not only "
    "the life of the individual, but success in leaving progeny. Two canine animals, in a "
    "time of dearth, may be truly said to struggle with each other which shall get food "
    "and live. But a plant on the edge of a desert is said to struggle for life against "
    "the drought, though more properly it should be said to be dependent on the moisture."
)
doc.add_paragraph("")

doc.add_paragraph("Geometrical Ratio of Increase")
doc.add_paragraph("")
doc.add_paragraph(
    "A struggle for existence inevitably follows from the high rate at which all organic "
    "beings tend to increase. Every being, which during its natural lifetime produces "
    "several eggs or seeds, must suffer destruction during some period of its life, and "
    "during some season or occasional year, otherwise, on the principle of geometrical "
    "increase, its numbers would quickly become so inordinately great that no country "
    "could support the product."
)
doc.add_paragraph("")

# --- CHAPTER IV ---
doc.add_paragraph("CHAPTER IV. NATURAL SELECTION")
doc.add_paragraph("")

doc.add_paragraph("Sexual Selection")
doc.add_paragraph("")
doc.add_paragraph(
    "This form of selection depends, not on a struggle for existence in relation to other "
    "organic beings or to external conditions, but on a struggle between the individuals "
    "of one sex, generally the males, for the possession of the other sex. The result is "
    "not death to the unsuccessful competitor, but few or no offspring. Sexual selection "
    "is, therefore, less rigorous than natural selection."
)
doc.add_paragraph("")

doc.add_paragraph("Illustrations of the Action of Natural Selection")
doc.add_paragraph("")
doc.add_paragraph(
    "In order to make it clear how, as I believe, natural selection acts, I must beg "
    "permission to give one or two imaginary illustrations. Let us take the case of a "
    "wolf, which preys on various animals, securing some by craft, some by strength, "
    "and some by fleetness; and let us suppose that the fleetest prey, a deer for "
    "instance, had from any change in the country increased in numbers, or that other "
    "prey had decreased in numbers, during that season of the year when the wolf was "
    "hardest pressed for food."
)

doc.save("/home/ga/Documents/origin_of_species_excerpt.docx")
print("Created document with Darwin's Origin of Species excerpt")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/origin_of_species_excerpt.docx
sudo chmod 666 /home/ga/Documents/origin_of_species_excerpt.docx

# Launch LibreOffice Writer with the document
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/origin_of_species_excerpt.docx > /tmp/writer_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/writer_task.log
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Writer" 90; then
    # Try alternate window title
    wait_for_window "origin_of_species" 30 || true
fi

# Click on center of screen to select desktop, then focus window
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Writer window
echo "Focusing Writer window..."
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        # Dismiss any "What's New" infobar that may appear on first launch
        safe_xdotool ga :1 key Escape
        sleep 0.3
        # Open Styles sidebar
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Move cursor to beginning of document
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Create Table of Contents Task Setup Complete ==="
echo "Instructions:"
echo "  1. Apply 'Heading 1' style to the 4 chapter titles"
echo "  2. Apply 'Heading 2' style to the 8 section headers"
echo "  3. Insert a Table of Contents at the beginning"
echo "  4. Save the document (Ctrl+S)"
