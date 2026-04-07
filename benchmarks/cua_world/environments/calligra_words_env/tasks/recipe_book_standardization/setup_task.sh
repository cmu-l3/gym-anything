#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Recipe Book Standardization Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop
kill_calligra_processes
rm -f /home/ga/Documents/recipe_manual_raw.odt
rm -f /home/ga/Desktop/recipe_style_guide.txt

# Create the Style Guide
cat << 'EOF' > /home/ga/Desktop/recipe_style_guide.txt
LUMIÈRE BISTRO - CORPORATE RECIPE MANUAL STYLE GUIDE

All restaurant recipes must be standardized according to the following rules:

1. MANUAL TITLE
   - The main title "LUMIÈRE BISTRO: STANDARDIZED RECIPE MANUAL" must be Bold, Centered, and at least 18pt font.
   - Insert a Table of Contents immediately following the main title.

2. RECIPE HEADINGS
   - The title of each recipe (e.g., Bouillabaisse) must be formatted as Heading 1.

3. SECTION HEADINGS
   - The subheadings "Ingredients", "Instructions", and "Allergens" must be formatted as Heading 2.

4. METADATA TABLES
   - The lines for Yield, Prep Time, and Cook Time must be converted into a single table for each recipe.
   - The table should ideally be 2 columns by 3 rows.

5. LISTS
   - All items under "Ingredients" must be formatted as a bulleted or numbered list.
   - All steps under "Instructions" must be formatted as a bulleted or numbered list.

6. ALLERGEN WARNINGS
   - The text listing the allergens (e.g., "Allergens: Fish, Shellfish, Allium") must be Bold to stand out to prep cooks.
EOF
chown ga:ga /home/ga/Desktop/recipe_style_guide.txt

# Create the unformatted document using odfpy
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

add_paragraph("LUMIÈRE BISTRO: STANDARDIZED RECIPE MANUAL")
add_paragraph("")

add_paragraph("Bouillabaisse")
add_paragraph("Yield: 6 portions")
add_paragraph("Prep Time: 45 minutes")
add_paragraph("Cook Time: 40 minutes")
add_paragraph("Ingredients")
add_paragraph("2 lbs mixed white fish (halibut, cod, snapper)")
add_paragraph("1 lb mussels, cleaned and debearded")
add_paragraph("1/2 cup olive oil")
add_paragraph("1 large onion, chopped")
add_paragraph("4 cloves garlic, minced")
add_paragraph("1 pinch saffron threads")
add_paragraph("Instructions")
add_paragraph("Heat olive oil in a large pot over medium heat.")
add_paragraph("Add onions and garlic, sauté until translucent.")
add_paragraph("Add saffron and fish stock, bring to a simmer.")
add_paragraph("Add fish and simmer for 10 minutes.")
add_paragraph("Add mussels and cook until they open.")
add_paragraph("Allergens: Fish, Shellfish, Allium")
add_paragraph("")

add_paragraph("Duck Confit")
add_paragraph("Yield: 4 portions")
add_paragraph("Prep Time: 24 hours")
add_paragraph("Cook Time: 3 hours")
add_paragraph("Ingredients")
add_paragraph("4 duck legs")
add_paragraph("3 tablespoons kosher salt")
add_paragraph("4 cups duck fat")
add_paragraph("3 sprigs fresh thyme")
add_paragraph("2 cloves garlic, crushed")
add_paragraph("Instructions")
add_paragraph("Rub duck legs with salt and refrigerate for 24 hours.")
add_paragraph("Rinse duck legs and pat dry.")
add_paragraph("Submerge duck legs in melted duck fat with thyme and garlic.")
add_paragraph("Cook at 225°F (107°C) for 3 hours until tender.")
add_paragraph("Allergens: Allium")
add_paragraph("")

add_paragraph("Beef Bourguignon")
add_paragraph("Yield: 8 portions")
add_paragraph("Prep Time: 30 minutes")
add_paragraph("Cook Time: 3 hours")
add_paragraph("Ingredients")
add_paragraph("3 lbs beef chuck, cut into 2-inch cubes")
add_paragraph("1 bottle Burgundy wine")
add_paragraph("2 cups beef stock")
add_paragraph("1/2 lb pearl onions")
add_paragraph("1/2 lb mushrooms, quartered")
add_paragraph("Instructions")
add_paragraph("Brown beef cubes in a large Dutch oven.")
add_paragraph("Add wine and beef stock, bring to a simmer.")
add_paragraph("Cover and braise in a 300°F (150°C) oven for 2.5 hours.")
add_paragraph("Sauté pearl onions and mushrooms separately, then add to the stew.")
add_paragraph("Allergens: Allium, Sulfites")
add_paragraph("")

add_paragraph("Ratatouille")
add_paragraph("Yield: 6 portions")
add_paragraph("Prep Time: 20 minutes")
add_paragraph("Cook Time: 45 minutes")
add_paragraph("Ingredients")
add_paragraph("2 eggplants, diced")
add_paragraph("3 zucchini, diced")
add_paragraph("1 large onion, chopped")
add_paragraph("4 tomatoes, chopped")
add_paragraph("3 cloves garlic, minced")
add_paragraph("Instructions")
add_paragraph("Sauté eggplant and zucchini in olive oil until golden.")
add_paragraph("In a separate pan, sauté onions and garlic.")
add_paragraph("Combine all vegetables and add chopped tomatoes.")
add_paragraph("Simmer for 30 minutes until vegetables are tender.")
add_paragraph("Allergens: Allium, Nightshades")
add_paragraph("")

doc.save("/home/ga/Documents/recipe_manual_raw.odt")
PYEOF
chown ga:ga /home/ga/Documents/recipe_manual_raw.odt

# Launch Calligra Words
launch_calligra_document "/home/ga/Documents/recipe_manual_raw.odt"
wait_for_window "Calligra Words" 30
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

take_screenshot /tmp/task_initial_state.png ga

echo "=== Task Setup Complete ==="