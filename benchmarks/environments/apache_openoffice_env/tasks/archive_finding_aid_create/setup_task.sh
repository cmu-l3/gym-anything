#!/bin/bash
set -e
echo "=== Setting up Archive Finding Aid Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Prepare directories
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop

# 2. Clean up previous artifacts
rm -f /home/ga/Documents/Sterling_Finding_Aid.odt 2>/dev/null || true
rm -f /home/ga/Documents/collection_metadata.json 2>/dev/null || true

# 3. Create the input JSON file with collection metadata and flat inventory
# This simulates a database export that the agent must organize.
cat > /home/ga/Documents/collection_metadata.json << 'EOF'
{
  "collection_info": {
    "title": "The Sterling Radiator Company Records",
    "id": "MS-2024-089",
    "dates": "1922-1965",
    "creator": "Sterling Radiator Company",
    "extent": "4.5 linear feet (9 document boxes)",
    "abstract": "Records of the Sterling Radiator Company, a Cleveland-based manufacturer of residential and commercial heating equipment. The collection documents the company's founding, financial growth, marketing strategies, and product development.",
    "biographical_history": "The Sterling Radiator Company was founded in 1922 by engineer Thomas Sterling in Cleveland, Ohio. Originally producing cast-iron radiators for steam heating, the company expanded into baseboard heaters and commercial boilers in the 1940s. During WWII, the factory converted to produce munitions components. Post-war, the company capitalized on the suburban housing boom. The company was acquired by Ohio General Industries in 1966.",
    "scope_and_contents": "The collection is organized into four series: Administrative Records, Financial Records, Marketing and Sales, and Technical Drawings. It includes board minutes, annual ledgers, product catalogs, advertising scrapbooks, and patent blueprints."
  },
  "inventory_items": [
    {"box": 1, "folder": 1, "title": "Articles of Incorporation and Bylaws", "date": "1922", "series": "Series I: Administrative Records"},
    {"box": 1, "folder": 2, "title": "Board of Directors Meeting Minutes", "date": "1922-1930", "series": "Series I: Administrative Records"},
    {"box": 1, "folder": 3, "title": "Board of Directors Meeting Minutes", "date": "1931-1945", "series": "Series I: Administrative Records"},
    {"box": 1, "folder": 4, "title": "Annual Reports to Shareholders", "date": "1925-1950", "series": "Series I: Administrative Records"},
    {"box": 2, "folder": 1, "title": "General Ledgers", "date": "1922-1935", "series": "Series II: Financial Records"},
    {"box": 2, "folder": 2, "title": "General Ledgers", "date": "1936-1949", "series": "Series II: Financial Records"},
    {"box": 2, "folder": 3, "title": "Federal Tax Returns", "date": "1940-1955", "series": "Series II: Financial Records"},
    {"box": 2, "folder": 4, "title": "Factory Payroll Registers", "date": "1942-1945", "series": "Series II: Financial Records"},
    {"box": 3, "folder": 1, "title": "Product Catalogs: Cast Iron Radiators", "date": "1925-1940", "series": "Series III: Marketing and Sales"},
    {"box": 3, "folder": 2, "title": "Product Catalogs: Baseboard Heaters", "date": "1945-1960", "series": "Series III: Marketing and Sales"},
    {"box": 3, "folder": 3, "title": "Magazine Advertisements (Scrapbook)", "date": "1930-1950", "series": "Series III: Marketing and Sales"},
    {"box": 3, "folder": 4, "title": "Sales Representative Correspondence", "date": "1950-1955", "series": "Series III: Marketing and Sales"},
    {"box": 4, "folder": 1, "title": "Patent 1,405,223: Steam Valve Mechanism", "date": "1923", "series": "Series IV: Technical Drawings"},
    {"box": 4, "folder": 2, "title": "Blueprints: Factory Layout Expansion", "date": "1941", "series": "Series IV: Technical Drawings"},
    {"box": 4, "folder": 3, "title": "R&D Lab Notebooks", "date": "1955-1960", "series": "Series IV: Technical Drawings"}
  ]
}
EOF
chown ga:ga /home/ga/Documents/collection_metadata.json

# 4. Ensure Desktop Shortcut exists (Task starts with OpenOffice NOT running)
if [ ! -f /home/ga/Desktop/openoffice-writer.desktop ]; then
    cat > /home/ga/Desktop/openoffice-writer.desktop << 'DESKTOP'
[Desktop Entry]
Version=1.0
Type=Application
Name=OpenOffice Writer
Comment=Create and edit text documents
Exec=/opt/openoffice4/program/soffice --writer %U
Icon=/opt/openoffice4/program/soffice
Terminal=false
Categories=Office;WordProcessor;
DESKTOP
    chown ga:ga /home/ga/Desktop/openoffice-writer.desktop
    chmod +x /home/ga/Desktop/openoffice-writer.desktop
fi

# 5. Record initial state timestamps
date +%s > /tmp/task_start_time.txt

# 6. Take initial screenshot (Desktop state)
take_screenshot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Input: /home/ga/Documents/collection_metadata.json"
echo "Target: /home/ga/Documents/Sterling_Finding_Aid.odt"