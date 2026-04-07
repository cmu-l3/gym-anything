#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Restaurant Menu Formatting Task ==="

kill_calligra_processes

install -d -o ga -g ga /home/ga/Documents

rm -f /home/ga/Documents/spring_menu_raw.odt

# ------------------------------------------------------------------
# Create the unformatted Menu with inline allergen notes
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add(text=""):
    doc.text.addElement(P(text=text))

add("Spring Tasting Menu")
add("")
add("STARTERS")
add("Spring Pea Soup")
add("Mint, crème fraîche, Meyer lemon oil. [Allergens: Dairy]")
add("$14")
add("")
add("Crab Cakes")
add("Lump blue crab, remoulade, pickled fennel. [Allergens: Shellfish, Gluten, Eggs]")
add("$22")
add("")
add("Burrata & Stone Fruit")
add("Local peaches, basil, aged balsamic, grilled sourdough. [Allergens: Dairy, Gluten]")
add("$18")
add("")
add("MAINS")
add("Miso Glazed Black Cod")
add("Bok choy, shiitake dashi, scallion. [Allergens: Soy]")
add("$38")
add("")
add("Spring Lamb Loin")
add("Asparagus, morel mushrooms, potato purée, lamb jus. [Allergens: Dairy]")
add("$42")
add("")
add("Wild Mushroom Risotto")
add("Arborio rice, English peas, Parmigiano-Reggiano, truffle oil. [Allergens: Dairy]")
add("$28")
add("")
add("DESSERTS")
add("Pistachio Rosewater Pavlova")
add("Meringue, pistachio cream, fresh raspberries. [Allergens: Nuts, Dairy, Eggs]")
add("$14")
add("")
add("Dark Chocolate Torte")
add("Valrhona chocolate, sea salt, vanilla bean ice cream. [Allergens: Dairy, Eggs, Gluten]")
add("$15")
add("")
add("Lemon Basil Sorbet")
add("Candied lemon zest, micro basil. [Allergens: None]")
add("$10")

doc.save("/home/ga/Documents/spring_menu_raw.odt")
PYEOF

chown ga:ga /home/ga/Documents/spring_menu_raw.odt

# Record task start time & size for anti-gaming verification
date +%s > /tmp/task_start_time.txt
stat -c %s /home/ga/Documents/spring_menu_raw.odt > /tmp/initial_file_size.txt

# Launch Calligra Words with the document
echo "Starting Calligra Words..."
launch_calligra_document "/home/ga/Documents/spring_menu_raw.odt"

# Wait for window, maximize, and focus
wait_for_window "Calligra Words" 30 || true

WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="