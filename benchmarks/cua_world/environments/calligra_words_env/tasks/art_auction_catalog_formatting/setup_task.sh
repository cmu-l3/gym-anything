#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Art Auction Catalog Formatting Task ==="

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

kill_calligra_processes
rm -f /home/ga/Documents/auction_inventory.odt
rm -f /home/ga/Desktop/catalog_style_guide.txt

# Create the style guide
cat > /home/ga/Desktop/catalog_style_guide.txt << 'EOF'
IMPRESSIONIST & MODERN ART CATALOG STYLE GUIDE
----------------------------------------------
1. MAIN TITLE ("Impressionist & Modern Art Evening Sale")
   - Alignment: Centered
   - Font Weight: Bold
   - Font Size: 18pt or larger

2. INTRODUCTORY SECTIONS
   - "Conditions of Sale" and "Auction Information" must be formatted as Heading 1.

3. ARTWORK LOTS (LOT 1 through LOT 15)
   - "LOT X" line: Format as Heading 2.
   - Artist Name (the line immediately following the lot number): Apply Bold formatting.
   - Artwork Title (the line immediately following the artist name): Apply Italic formatting.
   - Estimate line: Must be Right-aligned.

4. METADATA PREFIXES
   - The words "Provenance:", "Exhibited:", and "Literature:" (including the colon) must be Bolded wherever they appear in the lot descriptions.

5. ALL OTHER TEXT
   - Leave as default (Left-aligned, regular weight, 12pt).
EOF
chown ga:ga /home/ga/Desktop/catalog_style_guide.txt

# Create the ODT file using Python odfpy
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

add_paragraph("Impressionist & Modern Art Evening Sale")
add_paragraph("New York | May 15, 2026")
add_paragraph("")
add_paragraph("Conditions of Sale")
add_paragraph("The following conditions of sale and the terms of guarantee constitute the entire agreement with the purchaser relative to the property listed in this catalog. By bidding at auction, whether present in person or by agent, by written bid, telephone, or other means, the buyer agrees to be bound by these conditions of sale.")
add_paragraph("")
add_paragraph("Auction Information")
add_paragraph("A buyer's premium will be added to the successful bid price and is payable by the purchaser as part of the total purchase price. The buyer's premium is 25% of the hammer price up to and including $1,000,000, 20% of any amount in excess of $1,000,000 up to and including $6,000,000, and 14.5% of any amount in excess of $6,000,000.")
add_paragraph("")

lots_data = [
    ("Vincent van Gogh", "A Wheatfield with Cypresses", "Oil on canvas, 1889", "$25,000,000 - $35,000,000"),
    ("Claude Monet", "Bridge over a Pond of Water Lilies", "Oil on canvas, 1899", "$18,000,000 - $25,000,000"),
    ("Edgar Degas", "The Dance Class", "Oil on canvas, 1874", "$15,000,000 - $20,000,000"),
    ("Paul Cézanne", "Mont Sainte-Victoire", "Oil on canvas, 1902", "$30,000,000 - $40,000,000"),
    ("Pierre-Auguste Renoir", "By the Seashore", "Oil on canvas, 1883", "$12,000,000 - $18,000,000"),
    ("Camille Pissarro", "Boulevard Montmartre on a Winter Morning", "Oil on canvas, 1897", "$8,000,000 - $12,000,000"),
    ("Edouard Manet", "Boating", "Oil on canvas, 1874", "$20,000,000 - $30,000,000"),
    ("Georges Seurat", "A Sunday on La Grande Jatte (Study)", "Oil on canvas, 1884", "$10,000,000 - $15,000,000"),
    ("Paul Gauguin", "Ia Orana Maria (Hail Mary)", "Oil on canvas, 1891", "$22,000,000 - $28,000,000"),
    ("Henri de Toulouse-Lautrec", "At the Moulin Rouge", "Oil on canvas, 1892", "$14,000,000 - $18,000,000"),
    ("Auguste Rodin", "The Thinker", "Bronze sculpture, 1904", "$8,000,000 - $12,000,000"),
    ("Mary Cassatt", "The Child's Bath", "Oil on canvas, 1893", "$9,000,000 - $14,000,000"),
    ("Berthe Morisot", "The Mother and Sister of the Artist", "Oil on canvas, 1869", "$5,000,000 - $7,000,000"),
    ("Alfred Sisley", "The Bridge at Villeneuve-la-Garenne", "Oil on canvas, 1872", "$4,000,000 - $6,000,000"),
    ("Gustave Caillebotte", "Paris Street; Rainy Day", "Oil on canvas, 1877", "$28,000,000 - $35,000,000")
]

for i, lot in enumerate(lots_data):
    add_paragraph(f"LOT {i+1}")
    add_paragraph(lot[0])
    add_paragraph(lot[1])
    add_paragraph(lot[2])
    add_paragraph(f"Estimate: {lot[3]}")
    add_paragraph("Provenance: Private collection, Paris; acquired directly from the artist.")
    add_paragraph("Exhibited: Paris, Salon d'Automne; London, Royal Academy of Arts.")
    add_paragraph(f"Literature: J. Smith, Catalogue Raisonne, Vol II, no. {100+i}, p. {45+i}.")
    add_paragraph("")

doc.save("/home/ga/Documents/auction_inventory.odt")
PYEOF
chown ga:ga /home/ga/Documents/auction_inventory.odt

# Record task start time
echo "$(date +%s)" > /tmp/task_start_time.txt

# Launch Calligra Words
launch_calligra_document "/home/ga/Documents/auction_inventory.odt" "/tmp/calligra_task.log"

# Wait for window
wait_for_window "Calligra Words" 30

WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r "Calligra Words" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    # Dismiss any dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot "/tmp/task_initial.png"

echo "=== Task setup complete ==="