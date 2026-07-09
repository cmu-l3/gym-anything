#!/bin/bash
# pre_task hook for build_recipe_smart_folder on Finder/macOS.
#
# Seeds 20 recipe .txt files in ~/Downloads with human-readable names.
# The file names encode cuisine type; agent must classify and sort them.
set -eu

echo "=== Setting up build_recipe_smart_folder ==="

DOWNLOADS="$HOME/Downloads"
RECIPES="$HOME/Documents/Recipes"

# 1) Clean slate
mkdir -p "$DOWNLOADS"
/usr/bin/find "$DOWNLOADS" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
rm -rf "$RECIPES" 2>/dev/null || true
rm -f "$HOME/Library/Saved Searches/My Recipes.savedSearch" 2>/dev/null || true

# 2) Seed 20 recipe .txt files
seed_recipe() {
  local name="$1"
  local body="$2"
  /bin/echo "$body" > "$DOWNLOADS/$name"
}

# Italian (5)
seed_recipe "Pasta Carbonara from Nonna.txt"       "Spaghetti, guanciale, eggs, pecorino, black pepper."
seed_recipe "Homemade Margherita Pizza.txt"         "Dough, tomato sauce, mozzarella, fresh basil."
seed_recipe "Risotto ai Funghi.txt"                 "Arborio rice, porcini mushrooms, parmesan, butter."
seed_recipe "Tiramisu Classic.txt"                  "Ladyfingers, mascarpone, espresso, cocoa powder."
seed_recipe "Osso Buco Milanese.txt"                "Veal shanks, gremolata, saffron risotto."

# Asian (5)
seed_recipe "Pad Thai Noodles.txt"                  "Rice noodles, tofu, shrimp, peanuts, tamarind."
seed_recipe "Japanese Miso Soup.txt"                "Dashi, miso paste, tofu, wakame, green onion."
seed_recipe "Korean Bibimbap Bowl.txt"              "Steamed rice, assorted namul, gochujang, fried egg."
seed_recipe "Chicken Fried Rice Easy.txt"           "Leftover rice, egg, soy sauce, sesame oil, scallion."
seed_recipe "Vietnamese Pho Broth.txt"              "Beef bones, star anise, ginger, fish sauce, noodles."

# Mexican (4)
seed_recipe "Street Tacos al Pastor.txt"            "Pork shoulder, achiote, pineapple, corn tortilla."
seed_recipe "Homemade Guacamole.txt"               "Avocado, lime, cilantro, jalapeño, red onion."
seed_recipe "Black Bean Enchiladas.txt"             "Black beans, corn tortilla, red sauce, cheese."
seed_recipe "Churros with Chocolate.txt"            "Choux pastry, cinnamon sugar, dark chocolate dip."

# Baking (3)
seed_recipe "Sourdough Bread Beginner.txt"          "Bread flour, water, sourdough starter, sea salt."
seed_recipe "Chocolate Chip Cookies Classic.txt"    "Butter, brown sugar, eggs, vanilla, chocolate chips."
seed_recipe "Banana Bread Moist.txt"               "Overripe bananas, butter, brown sugar, flour, egg."

# Other (3)
seed_recipe "Greek Salad Simple.txt"               "Tomato, cucumber, olives, feta, red onion, oregano."
seed_recipe "Moroccan Lamb Tagine.txt"             "Lamb shoulder, preserved lemon, olives, couscous."
seed_recipe "French Onion Soup.txt"               "Caramelized onions, beef broth, gruyere, baguette."

SEED_COUNT=$(/usr/bin/find "$DOWNLOADS" -mindepth 1 -maxdepth 1 -name "*.txt" -type f 2>/dev/null | wc -l | tr -d ' ')
echo "seeded_file_count=$SEED_COUNT (expected: 20)"
if [ "${SEED_COUNT:-0}" -lt 20 ]; then
  echo "ERROR: setup failed to seed all 20 files" >&2
  exit 1
fi

mkdir -p "$HOME/Documents"

# 3) Record task start timestamp
/bin/date +%s > /tmp/task_start_timestamp
echo "task_start_unix=$(cat /tmp/task_start_timestamp)"

# 4) Ensure Finder is running and open Downloads
if ! /usr/bin/pgrep -x Finder >/dev/null 2>&1; then
  /usr/bin/open -a Finder
fi
for i in $(seq 1 15); do
  if /usr/bin/pgrep -x Finder >/dev/null 2>&1; then break; fi
  sleep 1
done

/usr/bin/open "$DOWNLOADS"
sleep 2
osascript -e 'tell application "Finder" to set current view of front window to column view' 2>/dev/null || true
sleep 1

# 5) Start-state screenshot
/usr/sbin/screencapture -x /tmp/task_start.png 2>/dev/null || true

echo "=== build_recipe_smart_folder setup complete ==="
echo "20 recipe .txt files seeded in ~/Downloads. Agent should sort into ~/Documents/Recipes/{Italian,Asian,Mexican,Baking,Other}/, rename to lowercase_underscore, apply Yellow tag, and create Smart Folder."
