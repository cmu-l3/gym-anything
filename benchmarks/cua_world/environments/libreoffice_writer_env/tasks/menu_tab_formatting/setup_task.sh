#!/bin/bash
# setup_task.sh — Restaurant Menu Tab Formatting Task
set -e

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Menu Formatting Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Record task start timestamp for verifier
date +%s > /tmp/task_start_time
chown ga:ga /tmp/task_start_time 2>/dev/null || true

# Generate the raw menu document using python-docx
# We create a messy, plain-text document that needs specific formatting
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt

doc = Document()

# Add Header Lines (Plain text, left aligned)
doc.add_paragraph("HARTWELL'S KITCHEN & BAR")
doc.add_paragraph("Portland, Oregon — Est. 2019")
doc.add_paragraph("")

# Helper to add items
def add_category(name, items):
    doc.add_paragraph(name) # Should be Heading 2
    for item, price, desc in items:
        # Messy format: Item $Price (Description)
        text = f"{item} ${price} ({desc})"
        doc.add_paragraph(text)
    doc.add_paragraph("")

# Menu Content
starters = [
    ("Crispy Brussels Sprouts", "12", "Flash-fried and tossed with honey-Sriracha glaze, sesame seeds"),
    ("Truffle Fries", "9", "Hand-cut fries, parmesan, white truffle oil, garlic aioli"),
    ("Steamed Mussels", "16", "White wine, garlic, shallots, butter, grilled baguette"),
    ("Deviled Eggs", "8", "Candied bacon, chives, smoked paprika"),
    ("Charcuterie Board", "24", "Chef's selection of cured meats, artisan cheeses, pickles, mustard")
]

soups = [
    ("Tomato Basil Bisque", "7", "Roasted tomatoes, fresh basil, cream, croutons"),
    ("French Onion Soup", "9", "Caramelized onions, beef broth, gruyère, crostini"),
    ("House Salad", "8", "Mixed greens, cucumber, cherry tomatoes, balsamic vinaigrette"),
    ("Caesar Salad", "10", "Romaine hearts, parmesan crisp, house-made dressing, anchovies")
]

entrees = [
    ("Steak Frites", "32", "10oz NY Strip, herb butter, hand-cut fries"),
    ("Pan-Seared Salmon", "28", "Lemon-dill sauce, wild rice pilaf, asparagus"),
    ("Roasted Chicken", "24", "Half chicken, garlic mashed potatoes, seasonal vegetables, pan jus"),
    ("Vegetable Risotto", "22", "Arborio rice, seasonal squash, mushrooms, parmesan, white wine"),
    ("The Hartwell Burger", "18", "Brioche bun, aged cheddar, bacon jam, arugula, aioli"),
    ("Pork Chop", "29", "Bone-in chop, apple chutney, sweet potato mash")
]

sides = [
    ("Mac & Cheese", "9", "Three cheese blend, breadcrumbs"),
    ("Roasted Vegetables", "7", "Seasonal mix with herb oil"),
    ("Mashed Potatoes", "6", "Yukon gold, butter, chives"),
    ("Garlic Bread", "5", "Ciabatta, roasted garlic butter")
]

desserts = [
    ("Chocolate Lava Cake", "10", "Vanilla bean ice cream, berry coulis"),
    ("Crème Brûlée", "9", "Classic vanilla custard, caramelized sugar shell"),
    ("Seasonal Fruit Tart", "11", "Pastry cream, fresh berries, apricot glaze"),
    ("Affogato", "7", "Espresso poured over vanilla gelato")
]

beverages = [
    ("Craft Cocktails", "14", "Ask your server for our seasonal list"),
    ("Local Draft Beer", "7", "Rotating selection of Oregon brews"),
    ("House Wine", "9", "Red, White, or Rosé by the glass"),
    ("Soda / Iced Tea", "4", "Free refills"),
    ("Coffee", "4", "Stumptown Roasters blend")
]

add_category("Starters", starters)
add_category("Soups & Salads", soups)
add_category("Entrées", entrees)
add_category("Sides", sides)
add_category("Desserts", desserts)
add_category("Beverages", beverages)

doc.save("/home/ga/Documents/menu_raw.docx")
print("Created /home/ga/Documents/menu_raw.docx")
PYEOF

# Ensure permissions
chown ga:ga /home/ga/Documents/menu_raw.docx
chmod 666 /home/ga/Documents/menu_raw.docx

# Launch LibreOffice Writer with the file
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/menu_raw.docx > /tmp/writer.log 2>&1 &"

# Wait for process and window
wait_for_process "soffice" 20
wait_for_window "LibreOffice Writer" 60 || wait_for_window "menu_raw" 30

# Maximize window
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    
    # Dismiss any "Tip of the Day" or recovery dialogs
    sleep 2
    safe_xdotool ga :1 key Escape
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="