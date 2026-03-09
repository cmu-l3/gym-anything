#!/bin/bash
# Setup script for seasonal_menu_create task
set -e

echo "=== Setting up Seasonal Menu Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Prepare directories
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop

# 2. Clean up previous run artifacts
rm -f /home/ga/Documents/thornfield_spring_menu_2025.odt 2>/dev/null || true
rm -f /home/ga/Documents/menu_data.json 2>/dev/null || true
rm -f /home/ga/Documents/menu_guidelines.txt 2>/dev/null || true

# 3. Create Menu Data JSON
cat > /home/ga/Documents/menu_data.json << 'JSONEOF'
{
  "restaurant": {
    "name": "Thornfield Kitchen & Garden",
    "tagline": "Seasonal. Local. Intentional.",
    "address": "42 East Market Street, Rhinebeck, NY 12572",
    "phone": "(845) 516-4078",
    "website": "www.thornfieldkitchen.com",
    "executive_chef": "Marguerite Solano",
    "farm_partners": [
      "Hearty Roots Community Farm",
      "Northwind Farms",
      "Ronnybrook Farm Dairy"
    ]
  },
  "menu_title": "Spring 2025 Dinner Menu",
  "menu_categories": [
    {
      "category_name": "Starters",
      "items": [
        {"name": "Ramp & Ricotta Crostini", "description": "Foraged Catskill ramps, house-made sheep's milk ricotta, sourdough, chili oil", "price": 16, "dietary_flags": ["V"]},
        {"name": "Duck Liver Mousse", "description": "Northwind Farms duck liver, cognac gelée, cornichons, grilled brioche", "price": 19, "dietary_flags": []},
        {"name": "Asparagus Tempura", "description": "Hudson Valley asparagus, miso-yuzu dipping sauce, shiso", "price": 15, "dietary_flags": ["V", "VG", "DF"]},
        {"name": "Lamb Meatballs", "description": "Spiced lamb, roasted tomato sauce, yogurt, mint, pine nuts", "price": 17, "dietary_flags": ["GF"]},
        {"name": "Burrata & Pea Tendrils", "description": "Pugliese burrata, snap pea tendrils, lemon vinaigrette, Aleppo pepper", "price": 18, "dietary_flags": ["V", "GF"]}
      ]
    },
    {
      "category_name": "Soups & Salads",
      "items": [
        {"name": "Nettle & Potato Soup", "description": "Foraged stinging nettles, Yukon Gold potato, crème fraîche, chive oil", "price": 14, "dietary_flags": ["V", "GF"]},
        {"name": "Spring Panzanella", "description": "Heirloom radish, sugar snaps, fava beans, torn sourdough, green goddess", "price": 16, "dietary_flags": ["V"]},
        {"name": "Beet & Chèvre Salad", "description": "Roasted Chioggia beets, Coach Farm chèvre, arugula, candied walnuts, honey vinaigrette", "price": 15, "dietary_flags": ["V", "GF"]},
        {"name": "Watercress & Radish", "description": "Wild watercress, breakfast radish, soft egg, anchovy dressing, rye crumbs", "price": 13, "dietary_flags": []}
      ]
    },
    {
      "category_name": "Pasta & Grains",
      "items": [
        {"name": "Morel Mushroom Pappardelle", "description": "Hand-rolled pappardelle, foraged morels, ramp butter, Parmigiano-Reggiano", "price": 28, "dietary_flags": ["V"]},
        {"name": "Spring Risotto", "description": "Carnaroli rice, English peas, fiddlehead ferns, mascarpone, lemon zest", "price": 26, "dietary_flags": ["V", "GF"]},
        {"name": "Farro Bowl", "description": "Emmer farro, roasted carrots, pickled turnips, tahini, dukkah", "price": 22, "dietary_flags": ["VG", "DF"]},
        {"name": "Ricotta Gnudi", "description": "House-made gnudi, brown butter, crispy sage, toasted hazelnuts", "price": 25, "dietary_flags": ["V"]},
        {"name": "Ramp Pesto Linguine", "description": "Bronze-die linguine, wild ramp pesto, spring garlic, pecorino, pine nuts", "price": 24, "dietary_flags": ["V"]}
      ]
    },
    {
      "category_name": "Seafood",
      "items": [
        {"name": "Pan-Roasted Hudson Valley Trout", "description": "Whole boned trout, brown butter, capers, haricots verts, new potatoes", "price": 34, "dietary_flags": ["GF"]},
        {"name": "Diver Scallops", "description": "Day-boat scallops, cauliflower purée, golden raisin agrodolce, fried capers", "price": 38, "dietary_flags": ["GF"]},
        {"name": "Montauk Striped Bass", "description": "Wild striped bass, spring vegetable nage, leeks, fingerling potatoes, dill oil", "price": 36, "dietary_flags": ["GF", "DF"]},
        {"name": "Lobster & Asparagus Risotto", "description": "Maine lobster tail, asparagus tips, saffron Carnaroli rice, tarragon butter", "price": 42, "dietary_flags": ["GF"]}
      ]
    },
    {
      "category_name": "Meat & Poultry",
      "items": [
        {"name": "Northwind Farms Duck Breast", "description": "Dry-aged Moulard duck, rhubarb compote, turnip gratin, watercress", "price": 38, "dietary_flags": ["GF"]},
        {"name": "Grass-Fed NY Strip", "description": "14oz dry-aged NY strip, bone marrow butter, roasted cipollini, pommes purée", "price": 46, "dietary_flags": ["GF"]},
        {"name": "Braised Lamb Shank", "description": "Slow-braised lamb shank, white bean ragout, gremolata, olive oil", "price": 36, "dietary_flags": ["GF", "DF"]},
        {"name": "Roasted Heritage Chicken", "description": "Half heritage breed chicken, lemon-herb jus, spring vegetables, fondant potato", "price": 32, "dietary_flags": ["GF"]},
        {"name": "Berkshire Pork Chop", "description": "Double-cut Berkshire pork, apple-cider gastrique, braised greens, sweet potato", "price": 34, "dietary_flags": ["GF", "DF"]}
      ]
    },
    {
      "category_name": "Desserts",
      "items": [
        {"name": "Meyer Lemon Tart", "description": "Meyer lemon curd, Italian meringue, shortbread crust, lemon verbena", "price": 14, "dietary_flags": ["V"]},
        {"name": "Chocolate Fondant", "description": "Valrhona dark chocolate, molten center, crème anglaise, sea salt", "price": 16, "dietary_flags": ["V"]},
        {"name": "Strawberry Pavlova", "description": "Crisp meringue, Migliorelli Farm strawberries, Chantilly cream, basil", "price": 15, "dietary_flags": ["V", "GF"]},
        {"name": "Maple Crème Brûlée", "description": "Crown Maple syrup custard, caramelized sugar, shortbread cookie", "price": 13, "dietary_flags": ["V", "GF"]},
        {"name": "Farmstead Cheese Plate", "description": "Three regional cheeses, seasonal fruit, honeycomb, toasted nuts, crackers", "price": 18, "dietary_flags": ["V"]}
      ]
    }
  ],
  "dietary_legend": {
    "V": "Vegetarian",
    "VG": "Vegan",
    "GF": "Gluten-Free",
    "DF": "Dairy-Free"
  },
  "chef_note": "Our Spring 2025 menu celebrates the first harvests of the Hudson Valley growing season."
}
JSONEOF

# 4. Create Guidelines Text
cat > /home/ga/Documents/menu_guidelines.txt << 'TXTEOF'
THORNFIELD KITCHEN & GARDEN — Menu Document Formatting Standards
================================================================

This document describes the formatting requirements for all printed
menu documents. The office manager must follow these guidelines when
preparing menu files for the print shop.

DOCUMENT STRUCTURE:
- Document title: Restaurant name and menu title at the top
- Table of Contents: Auto-generated, inserted after the title block
- Course categories (Starters, Soups & Salads, etc.): Use Heading 1 style
- Subsections (Dietary Legend, Chef's Note): Use Heading 2 style
- Menu items within each category: Use a TABLE with columns for
  Dish Name, Description, and Price
- Each course category must have its own table

FORMATTING RULES:
1. All main course category names must use the Heading 1 paragraph style
   (NOT manual bold/font size — use the actual Writer style)
2. Supplementary sections (dietary legend, chef's note) use Heading 2
3. Each category's dishes listed in a 3-column table:
   Column 1: Dish Name (include dietary flags in parentheses if applicable)
   Column 2: Description
   Column 3: Price (formatted as dollar amount, e.g., "$16")
4. Include a Dietary Legend section explaining flag abbreviations
5. Include the Chef's Note section with the seasonal statement
6. Page numbers must appear in the document footer
7. Table of Contents must be auto-generated (Insert > Indexes and Tables)

SAVE INSTRUCTIONS:
- Filename: thornfield_spring_menu_2025.odt
- Location: /home/ga/Documents/
- Format: ODF Text Document (.odt)
TXTEOF

# 5. Fix permissions
chown ga:ga /home/ga/Documents/menu_data.json
chown ga:ga /home/ga/Documents/menu_guidelines.txt

# 6. Ensure desktop shortcut exists (crucial for agent to find app)
if [ ! -f "/home/ga/Desktop/OpenOffice-Writer.desktop" ]; then
    cp /usr/share/applications/openoffice4-writer.desktop /home/ga/Desktop/OpenOffice-Writer.desktop 2>/dev/null || \
    cat > /home/ga/Desktop/OpenOffice-Writer.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=OpenOffice Writer
Comment=Apache OpenOffice Word Processor
Exec=/opt/openoffice4/program/soffice --writer %U
Icon=openoffice4-writer
Terminal=false
Type=Application
Categories=Office;WordProcessor;
DESKTOPEOF
fi
chown ga:ga /home/ga/Desktop/OpenOffice-Writer.desktop
chmod +x /home/ga/Desktop/OpenOffice-Writer.desktop

# 7. Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 8. Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="