#!/bin/bash
echo "=== Setting up museum_collection_logistics task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

DOC_DIR="/home/ga/Documents"
mkdir -p "$DOC_DIR"

CSV_FILE="$DOC_DIR/moma_exhibition_subset.csv"
rm -f "$CSV_FILE" "$DOC_DIR/moma_logistics.xlsx" 2>/dev/null || true

# Generate realistic MoMA subset data
python3 << 'PYEOF'
import csv
import random

# Real historical artwork data from MoMA
artworks = [
    ["The Starry Night", "Vincent van Gogh", "1889", "Oil on canvas", "73.7 x 92.1 cm", "Painting", "Painting & Sculpture", "1941", 73.7, 92.1, 0, 8.5],
    ["Les Demoiselles d'Avignon", "Pablo Picasso", "1907", "Oil on canvas", "243.9 x 233.7 cm", "Painting", "Painting & Sculpture", "1939", 243.9, 233.7, 0, 45.2],
    ["The Persistence of Memory", "Salvador Dalí", "1931", "Oil on canvas", "24 x 33 cm", "Painting", "Painting & Sculpture", "1934", 24, 33, 0, 1.2],
    ["Water Lilies", "Claude Monet", "1914", "Oil on canvas", "200 x 425 cm", "Painting", "Painting & Sculpture", "1959", 200, 425, 0, 55.4],
    ["Campbell's Soup Cans", "Andy Warhol", "1962", "Synthetic polymer paint on canvas", "50.8 x 40.6 cm", "Painting", "Painting & Sculpture", "1996", 50.8, 40.6, 0, 1.5],
    ["Bicycle Wheel", "Marcel Duchamp", "1951", "Metal wheel mounted on painted wood stool", "129.5 x 63.5 x 31.8 cm", "Sculpture", "Painting & Sculpture", "1964", 129.5, 63.5, 31.8, 12.0],
    ["Unique Forms of Continuity in Space", "Umberto Boccioni", "1913", "Bronze", "111.2 x 88.5 x 40 cm", "Sculpture", "Painting & Sculpture", "1948", 111.2, 88.5, 40, 65.5],
    ["The Lovers", "René Magritte", "1928", "Oil on canvas", "54 x 73.4 cm", "Painting", "Painting & Sculpture", "1998", 54, 73.4, 0, 3.4],
    ["One: Number 31, 1950", "Jackson Pollock", "1950", "Oil and enamel paint on canvas", "269.5 x 530.8 cm", "Painting", "Painting & Sculpture", "1968", 269.5, 530.8, 0, 85.0],
    ["Drowning Girl", "Roy Lichtenstein", "1963", "Oil and synthetic polymer paint on canvas", "171.6 x 169.5 cm", "Painting", "Painting & Sculpture", "1971", 171.6, 169.5, 0, 22.0],
    ["Bird in Space", "Constantin Brancusi", "1928", "Bronze", "137.2 x 21.6 x 21.6 cm", "Sculpture", "Painting & Sculpture", "1934", 137.2, 21.6, 21.6, 32.0],
    ["Fulang-Chang and I", "Frida Kahlo", "1937", "Oil on composition board", "40 x 28 cm", "Painting", "Painting & Sculpture", "1938", 40, 28, 0, 2.1],
    ["The Bather", "Paul Cézanne", "1885", "Oil on canvas", "127 x 96.8 cm", "Painting", "Painting & Sculpture", "1934", 127, 96.8, 0, 15.0],
    ["Gold Marilyn Monroe", "Andy Warhol", "1962", "Silkscreen ink on synthetic polymer paint on canvas", "211.4 x 144.7 cm", "Painting", "Painting & Sculpture", "1962", 211.4, 144.7, 0, 30.5],
    ["Three Musicians", "Pablo Picasso", "1921", "Oil on canvas", "200.7 x 222.9 cm", "Painting", "Painting & Sculpture", "1949", 200.7, 222.9, 0, 42.0],
    ["I and the Village", "Marc Chagall", "1911", "Oil on canvas", "192.1 x 151.4 cm", "Painting", "Painting & Sculpture", "1945", 192.1, 151.4, 0, 38.0],
    ["Dance (I)", "Henri Matisse", "1909", "Oil on canvas", "259.7 x 390.1 cm", "Painting", "Painting & Sculpture", "1937", 259.7, 390.1, 0, 75.0],
    ["Number 1A, 1948", "Jackson Pollock", "1948", "Oil and enamel paint on canvas", "172.7 x 264.2 cm", "Painting", "Painting & Sculpture", "1950", 172.7, 264.2, 0, 48.0],
    ["Christina's World", "Andrew Wyeth", "1948", "Tempera on panel", "81.9 x 121.3 cm", "Painting", "Painting & Sculpture", "1948", 81.9, 121.3, 0, 8.0],
    ["Vir Heroicus Sublimis", "Barnett Newman", "1950", "Oil on canvas", "242.2 x 541.7 cm", "Painting", "Painting & Sculpture", "1951", 242.2, 541.7, 0, 95.0],
    ["Study for a Pope", "Francis Bacon", "1953", "Oil on canvas", "153 x 118.1 cm", "Painting", "Painting & Sculpture", "1956", 153, 118.1, 0, 18.0],
    ["The False Mirror", "René Magritte", "1929", "Oil on canvas", "54 x 80.9 cm", "Painting", "Painting & Sculpture", "1943", 54, 80.9, 0, 4.0],
    ["The Sleeping Gypsy", "Henri Rousseau", "1897", "Oil on canvas", "129.5 x 200.7 cm", "Painting", "Painting & Sculpture", "1939", 129.5, 200.7, 0, 28.0],
    ["White on White", "Kazimir Malevich", "1918", "Oil on canvas", "79.4 x 79.4 cm", "Painting", "Painting & Sculpture", "1935", 79.4, 79.4, 0, 6.0],
    ["The City Rises", "Umberto Boccioni", "1910", "Oil on canvas", "199.3 x 301 cm", "Painting", "Painting & Sculpture", "1931", 199.3, 301, 0, 52.0],
    ["Composition in Red, Blue, and Yellow", "Piet Mondrian", "1930", "Oil on canvas", "46 x 46 cm", "Painting", "Painting & Sculpture", "1946", 46, 46, 0, 2.5],
    ["Guernica Sketch", "Pablo Picasso", "1937", "Pencil on paper", "21 x 31 cm", "Drawing", "Drawings", "1939", 21, 31, 0, 0.1],
    ["Untitled", "Lee Krasner", "1940", "Charcoal on paper", "63.5 x 48.2 cm", "Drawing", "Drawings", "1983", 63.5, 48.2, 0, 0.2],
    ["Woman Walking", "Alberto Giacometti", "1932", "Bronze", "150 x 28 x 38 cm", "Sculpture", "Painting & Sculpture", "1935", 150, 28, 38, 52.0],
    ["Self-Portrait", "Egon Schiele", "1912", "Watercolor and pencil on paper", "32 x 25 cm", "Drawing", "Drawings", "1950", 32, 25, 0, 0.1],
    ["The Steerage", "Alfred Stieglitz", "1907", "Photogravure on paper", "33.3 x 26.5 cm", "Photograph", "Photography", "1941", 33.3, 26.5, 0, 0.1],
    ["Moonrise, Hernandez", "Ansel Adams", "1941", "Gelatin silver print on paper", "40.6 x 50.8 cm", "Photograph", "Photography", "1945", 40.6, 50.8, 0, 0.2],
    ["Migrant Mother", "Dorothea Lange", "1936", "Gelatin silver print on paper", "28.3 x 21.8 cm", "Photograph", "Photography", "1941", 28.3, 21.8, 0, 0.1],
    ["Monument to Balzac", "Auguste Rodin", "1898", "Bronze", "270 x 120 x 128 cm", "Sculpture", "Painting & Sculpture", "1939", 270, 120, 128, 650.0],
    ["Standing Woman", "Gaston Lachaise", "1932", "Bronze", "223.5 x 104.1 x 53.3 cm", "Sculpture", "Painting & Sculpture", "1938", 223.5, 104.1, 53.3, 317.0],
    ["Maman", "Louise Bourgeois", "1999", "Bronze, marble, and stainless steel", "927.1 x 891.5 x 1023.6 cm", "Sculpture", "Painting & Sculpture", "2000", 927.1, 891.5, 1023.6, 8000.0],
    ["Spiral Jetty Sketch", "Robert Smithson", "1970", "Ink and pencil on paper", "22.9 x 30.5 cm", "Drawing", "Drawings", "1971", 22.9, 30.5, 0, 0.1],
    ["Cut with the Kitchen Knife", "Hannah Höch", "1919", "Photomontage and collage with watercolor on paper", "114 x 90 cm", "Drawing", "Drawings", "1940", 114, 90, 0, 0.3],
    ["Untitled (Stack)", "Donald Judd", "1967", "Lacquer on galvanized iron", "508 x 101.6 x 78.7 cm", "Sculpture", "Painting & Sculpture", "1968", 508, 101.6, 78.7, 120.0],
    ["Flag", "Jasper Johns", "1954", "Encaustic, oil, and collage on fabric mounted on plywood", "107.3 x 153.8 cm", "Painting", "Painting & Sculpture", "1973", 107.3, 153.8, 0, 25.0]
]

with open('/home/ga/Documents/moma_exhibition_subset.csv', 'w', newline='', encoding='utf-8') as f:
    writer = csv.writer(f)
    writer.writerow(["Title", "Artist", "Date", "Medium", "Dimensions", "Classification", "Department", "DateAcquired", "Height_cm", "Width_cm", "Depth_cm", "Weight_kg"])
    writer.writerows(artworks)
PYEOF

chown -R ga:ga "$DOC_DIR"

# Ensure WPS Spreadsheet is not running
pkill -f "et" 2>/dev/null || true
sleep 1

# Start WPS Spreadsheet with the target file
echo "Starting WPS Spreadsheet..."
su - ga -c "DISPLAY=:1 et /home/ga/Documents/moma_exhibition_subset.csv &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "moma_exhibition_subset"; then
        echo "WPS Spreadsheet window detected"
        break
    fi
    sleep 1
done

# Focus and maximize window
DISPLAY=:1 wmctrl -a "WPS Spreadsheets" 2>/dev/null || true
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Wait for UI to render
sleep 3
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="