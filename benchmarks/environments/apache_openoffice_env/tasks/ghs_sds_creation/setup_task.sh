#!/bin/bash
set -e
echo "=== Setting up GHS SDS Creation Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Ensure Documents directory exists and has correct permissions
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Clean up previous artifacts
rm -f /home/ga/Documents/SDS_ApexSolv5000.odt 2>/dev/null || true
rm -f /home/ga/Documents/product_data.json 2>/dev/null || true

# Create the Product Data JSON file
cat > /home/ga/Documents/product_data.json << 'EOF'
{
  "product_name": "Apex-Solv 5000",
  "manufacturer": {
    "name": "Apex Industrial Chemicals",
    "address": "4000 Chemical Way, Houston, TX 77002",
    "emergency_phone": "1-800-555-0911"
  },
  "sections": {
    "1": "Identification",
    "2": "Hazard(s) Identification",
    "3": "Composition/Information on Ingredients",
    "4": "First-Aid Measures",
    "5": "Fire-Fighting Measures",
    "6": "Accidental Release Measures",
    "7": "Handling and Storage",
    "8": "Exposure Controls/Personal Protection",
    "9": "Physical and Chemical Properties",
    "10": "Stability and Reactivity",
    "11": "Toxicological Information",
    "12": "Ecological Information",
    "13": "Disposal Considerations",
    "14": "Transport Information",
    "15": "Regulatory Information",
    "16": "Other Information"
  },
  "ingredients": [
    {
      "chemical_name": "Sodium Hydroxide",
      "cas_number": "1310-73-2",
      "concentration": "1-5%"
    },
    {
      "chemical_name": "2-Butoxyethanol",
      "cas_number": "111-76-2",
      "concentration": "5-10%"
    },
    {
      "chemical_name": "Sodium Metasilicate",
      "cas_number": "6834-92-0",
      "concentration": "1-5%"
    },
    {
      "chemical_name": "Water",
      "cas_number": "7732-18-5",
      "concentration": "Balance"
    }
  ],
  "hazard_classification": {
    "signal_word": "DANGER",
    "hazard_statements": [
      "H290: May be corrosive to metals",
      "H314: Causes severe skin burns and eye damage"
    ],
    "precautionary_statements": [
      "P260: Do not breathe dusts or mists.",
      "P280: Wear protective gloves/protective clothing/eye protection/face protection.",
      "P303+P361+P353: IF ON SKIN (or hair): Take off immediately all contaminated clothing. Rinse skin with water/shower."
    ]
  },
  "physical_properties": {
    "appearance": "Clear purple liquid",
    "ph": "13.5 - 14.0",
    "odor": "Mild solvent"
  }
}
EOF

# Set ownership
chown ga:ga /home/ga/Documents/product_data.json
chmod 644 /home/ga/Documents/product_data.json

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure OpenOffice Writer is NOT running (agent must launch it)
pkill -f soffice || true

# Ensure Desktop shortcut exists
if [ ! -f "/home/ga/Desktop/openoffice4-writer.desktop" ] && [ ! -f "/home/ga/Desktop/openoffice-writer.desktop" ]; then
    cp /usr/share/applications/openoffice4-writer.desktop /home/ga/Desktop/ 2>/dev/null || \
    cp /usr/share/applications/openoffice-writer.desktop /home/ga/Desktop/ 2>/dev/null || true
    chmod +x /home/ga/Desktop/*.desktop 2>/dev/null || true
    chown ga:ga /home/ga/Desktop/*.desktop 2>/dev/null || true
fi

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="