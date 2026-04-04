#!/bin/bash
# Setup script for csi_spec_section_write task

set -e
echo "=== Setting up CSI Spec Section Write Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Ensure directories exist
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop

# Clean up any previous task artifacts
rm -f /home/ga/Documents/093013_Ceramic_Tiling.odt 2>/dev/null || true
rm -f /home/ga/Documents/spec_data.json 2>/dev/null || true

# Create the spec_data.json file with realistic construction data
cat > /home/ga/Documents/spec_data.json << 'JSONEOF'
{
  "project_info": {
    "name": "Harborview Medical Center Expansion",
    "location": "Seattle, WA",
    "project_number": "2024-045",
    "date": "March 2026"
  },
  "section_info": {
    "number": "09 30 13",
    "title": "Ceramic Tiling"
  },
  "part_1_general": {
    "summary": "Section includes ceramic tile, stone thresholds, waterproof membranes, and crack isolation membranes.",
    "references": [
      "ANSI A108 Series - Installation of Ceramic Tile",
      "ANSI A118 Series - Specifications for Mortars and Grouts",
      "ANSI A137.1 - American National Standard Specifications for Ceramic Tile",
      "TCNA Handbook - Handbook for Ceramic, Glass, and Stone Tile Installation"
    ],
    "submittals": ["Product Data", "Samples", "Master Grade Certificates"],
    "quality_assurance": "Installer Qualifications: Company specializing in performing the work of this section with minimum 5 years documented experience."
  },
  "part_2_products": {
    "tile_products": [
      {
        "mark": "T-1",
        "type": "Porcelain Floor Tile",
        "finish": "Matte / Slip-Resistant",
        "size": "12 by 24 inches",
        "manufacturer": "Dal-Tile or approved equal",
        "location": "Public Restroom Floors, Lobby Corridors"
      },
      {
        "mark": "T-2",
        "type": "Glazed Ceramic Wall Tile",
        "finish": "Glossy / Bright",
        "size": "4 by 12 inches",
        "manufacturer": "Olympia Tile or approved equal",
        "location": "Restroom Wet Walls, Janitor Closets"
      }
    ],
    "setting_materials": {
      "mortar": "Modified Dry-Set Cement Mortar: ANSI A118.4.",
      "grout": "High-Performance Cement Grout: ANSI A118.7, color as selected by Architect."
    }
  },
  "part_3_execution": {
    "examination": "Verify that substrates are within tolerances and free of curing compounds.",
    "installation": "Install according to TCNA Handbook methods and ANSI A108 series.",
    "protection": "Protect installed tile work from traffic for 72 hours."
  }
}
JSONEOF

chown ga:ga /home/ga/Documents/spec_data.json
chmod 644 /home/ga/Documents/spec_data.json

# Record start state
echo "0" > /tmp/initial_file_exists
date +%s > /tmp/task_start_timestamp

# Ensure OpenOffice Writer is running and ready
if ! pgrep -f "soffice" > /dev/null 2>&1; then
    echo "Starting OpenOffice Writer..."
    # Launch in background as user ga
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
    
    # Wait for window
    for i in {1..30}; do
        if wmctrl -l | grep -qi "OpenOffice Writer"; then
            echo "OpenOffice Writer window detected"
            break
        fi
        sleep 1
    done
    sleep 5
else
    echo "OpenOffice Writer is already running"
fi

# Focus and maximize
wid=$(wmctrl -l | grep -i "OpenOffice Writer" | awk '{print $1}' | head -1)
if [ -n "$wid" ]; then
    wmctrl -i -a "$wid"
    wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete: spec_data.json created ==="