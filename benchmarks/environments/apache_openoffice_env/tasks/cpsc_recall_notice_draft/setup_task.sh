#!/bin/bash
set -e
echo "=== Setting up CPSC Recall Notice Draft Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Create Documents directory
sudo -u ga mkdir -p /home/ga/Documents

# Clean up any existing files
rm -f /home/ga/Documents/Steamfast_Recall_Draft.odt 2>/dev/null || true
rm -f /home/ga/Documents/recall_details.json 2>/dev/null || true

# Create the JSON data file with real recall information
cat > /home/ga/Documents/recall_details.json << 'EOF'
{
  "release_date": "April 27, 2023",
  "headline": "Vornado Air Recalls Steamfast Travel Steam Irons Due to Fire, Burn and Shock Hazards",
  "product_name": "Steamfast Home & Away Travel Steam Irons",
  "affected_models": [
    "SF-425", "SF-430", "SF-432", "SF-435", "SF-437",
    "SF-438", "SF-439", "SF-440", "SF-445", "SF-447"
  ],
  "hazard_description": "The power cord can become damaged near the cord bushing, posing fire, burn and shock hazards. The cord bushing can also overheat, posing a fire and burn hazard.",
  "remedy": "Refund or Replace",
  "consumer_contact": "Vornado Air toll-free at 866-827-3362 from 8 a.m. to 5 p.m. ET Monday through Friday, or online at www.steamfast.com/recalls/travelirons.",
  "units": "About 2 million (In addition, about 13,000 were sold in Canada)",
  "incidents_injuries": {
    "total_reports": 74,
    "cord_damage_reports": 18,
    "minor_burns": 2
  },
  "description": "This recall involves Steamfast brand Home & Away Travel Steam Irons with model numbers listed above. The model number is printed on the bottom of the irons. The irons were sold in white."
}
EOF

# Set ownership
chown ga:ga /home/ga/Documents/recall_details.json
chmod 644 /home/ga/Documents/recall_details.json

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure OpenOffice Writer is available (create desktop shortcut if missing)
if [ ! -f "/home/ga/Desktop/openoffice-writer.desktop" ]; then
    mkdir -p /home/ga/Desktop
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
MimeType=application/vnd.oasis.opendocument.text;
DESKTOP
    chown ga:ga /home/ga/Desktop/openoffice-writer.desktop
    chmod +x /home/ga/Desktop/openoffice-writer.desktop
fi

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Data file created at: /home/ga/Documents/recall_details.json"