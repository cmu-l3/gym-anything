#!/bin/bash
# Setup script for exhibit_catalog_create task

echo "=== Setting up Exhibition Catalog Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Prepare directories
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop

# 2. Clean up previous artifacts
rm -f /home/ga/Documents/Light_in_Motion_Catalog.odt 2>/dev/null || true
rm -f /home/ga/Documents/exhibition_data.json 2>/dev/null || true

# 3. Create the exhibition data JSON file
cat > /home/ga/Documents/exhibition_data.json << 'EOF'
{
  "exhibition": {
    "title": "Light in Motion: Masterworks of French Impressionism",
    "subtitle": "A Loan Exhibition",
    "dates": "March 15 – July 27, 2025",
    "venue": {
      "name": "Hartwell Center for American Art",
      "address": "1820 Fairmount Avenue, Philadelphia, PA 19130",
      "gallery": "Whitfield Gallery, Second Floor"
    }
  },
  "curator": {
    "name": "Dr. Elaine Whitford",
    "title": "Senior Curator of European Painting",
    "foreword_text": "This exhibition traces the radical transformation of light and color that defined the late 19th century in France. By bringing together these eight masterworks, we invite the viewer to look beyond the subject matter and engage with the very act of seeing."
  },
  "artworks": [
    {
      "catalog_number": "LIM-001",
      "artist": "Claude Monet",
      "title": "Impression, Sunrise",
      "date": "1872",
      "medium": "Oil on canvas",
      "dimensions": "48 × 63 cm",
      "lender": "Musée Marmottan Monet, Paris"
    },
    {
      "catalog_number": "LIM-002",
      "artist": "Pierre-Auguste Renoir",
      "title": "Bal du moulin de la Galette",
      "date": "1876",
      "medium": "Oil on canvas",
      "dimensions": "131 × 175 cm",
      "lender": "Musée d'Orsay, Paris"
    },
    {
      "catalog_number": "LIM-003",
      "artist": "Edgar Degas",
      "title": "The Dance Class",
      "date": "1874",
      "medium": "Oil on canvas",
      "dimensions": "83.5 × 77.2 cm",
      "lender": "Metropolitan Museum of Art, New York"
    },
    {
      "catalog_number": "LIM-004",
      "artist": "Berthe Morisot",
      "title": "The Cradle",
      "date": "1872",
      "medium": "Oil on canvas",
      "dimensions": "56 × 46 cm",
      "lender": "Musée d'Orsay, Paris"
    },
    {
      "catalog_number": "LIM-005",
      "artist": "Gustave Caillebotte",
      "title": "Paris Street; Rainy Day",
      "date": "1877",
      "medium": "Oil on canvas",
      "dimensions": "212.2 × 276.2 cm",
      "lender": "Art Institute of Chicago"
    },
    {
      "catalog_number": "LIM-006",
      "artist": "Mary Cassatt",
      "title": "The Child's Bath",
      "date": "1893",
      "medium": "Oil on canvas",
      "dimensions": "100.3 × 66.1 cm",
      "lender": "Art Institute of Chicago"
    },
    {
      "catalog_number": "LIM-007",
      "artist": "Camille Pissarro",
      "title": "Boulevard Montmartre at Night",
      "date": "1897",
      "medium": "Oil on canvas",
      "dimensions": "53.3 × 64.8 cm",
      "lender": "National Gallery, London"
    },
    {
      "catalog_number": "LIM-008",
      "artist": "Alfred Sisley",
      "title": "Bridge at Villeneuve-la-Garenne",
      "date": "1872",
      "medium": "Oil on canvas",
      "dimensions": "49.5 × 65.4 cm",
      "lender": "Metropolitan Museum of Art, New York"
    }
  ],
  "required_sections": [
    "Table of Contents",
    "Curator's Foreword",
    "Exhibition Overview",
    "Catalog Entries",
    "Loan Acknowledgments",
    "Inventory Checklist (Table)"
  ]
}
EOF

chown ga:ga /home/ga/Documents/exhibition_data.json
chmod 644 /home/ga/Documents/exhibition_data.json

# 4. Record initial state timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 5. Launch OpenOffice Writer (Start with a blank document as requested)
echo "Launching OpenOffice Writer..."
if ! pgrep -f "soffice" > /dev/null; then
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
    sleep 5
fi

# 6. Wait for window and maximize
echo "Waiting for Writer window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenOffice Writer"; then
        echo "Writer detected."
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r "OpenOffice Writer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenOffice Writer" 2>/dev/null || true

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="