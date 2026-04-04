#!/bin/bash
# Setup script for landscape_maintenance_guide task

echo "=== Setting up Landscape Maintenance Guide Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# ensure directories
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop

# Clean up any previous task artifacts
rm -f /home/ga/Documents/Sullivan_Maintenance_Manual.odt 2>/dev/null || true
rm -f /home/ga/Documents/project_plants.json 2>/dev/null || true
rm -f /home/ga/Documents/plant_database.json 2>/dev/null || true

# 1. Create project_plants.json
cat > /home/ga/Documents/project_plants.json << 'EOF'
{
  "project_name": "Sullivan Residence",
  "install_date": "2024-05-15",
  "installed_plants": [
    {"scientific": "Acer palmatum", "common": "Japanese Maple"},
    {"scientific": "Hydrangea macrophylla", "common": "Bigleaf Hydrangea"},
    {"scientific": "Buxus sempervirens", "common": "American Boxwood"},
    {"scientific": "Lavandula angustifolia", "common": "English Lavender"},
    {"scientific": "Hosta sieboldiana", "common": "Giant Hosta"},
    {"scientific": "Cornus kousa", "common": "Kousa Dogwood"},
    {"scientific": "Miscanthus sinensis", "common": "Maiden Grass"},
    {"scientific": "Echinacea purpurea", "common": "Coneflower"},
    {"scientific": "Thuja occidentalis", "common": "Arborvitae"},
    {"scientific": "Pachysandra terminalis", "common": "Japanese Spurge"},
    {"scientific": "Rhododendron catawbiense", "common": "Catawba Rhododendron"},
    {"scientific": "Heuchera micrantha", "common": "Coral Bells"}
  ],
  "service_contacts": [
    {"service": "Irrigation", "company": "RainRight Systems", "phone": "(555) 010-2233"},
    {"service": "Lighting", "company": "Lumina Outdoor", "phone": "(555) 012-4455"},
    {"service": "Arborist", "company": "Valley Tree Care", "phone": "(555) 019-9988"}
  ]
}
EOF
chown ga:ga /home/ga/Documents/project_plants.json

# 2. Create plant_database.json (includes distractors)
cat > /home/ga/Documents/plant_database.json << 'EOF'
[
  {
    "common_name": "Japanese Maple",
    "care": {
      "Spring": "Apply slow-release fertilizer. Inspect for aphids.",
      "Summer": "Monitor for leaf scorch. Deep water bi-weekly.",
      "Fall": "Prune crossing branches. Rake leaves.",
      "Winter": "Apply mulch to root zone, avoiding trunk."
    }
  },
  {
    "common_name": "Bigleaf Hydrangea",
    "care": {
      "Spring": "Remove dead wood. Apply acidifier if blue blooms desired.",
      "Summer": "Water consistently to prevent wilting.",
      "Fall": "Do not prune (blooms on old wood).",
      "Winter": "Protect from harsh winds with burlap if exposed."
    }
  },
  {
    "common_name": "Hybrid Tea Rose",
    "care": {
      "Spring": "Prune hard to 12 inches. Fertilize heavily.",
      "Summer": "Deadhead spent blooms weekly.",
      "Fall": "Stop fertilizing to harden off.",
      "Winter": "Heap soil over crown for protection."
    }
  },
  {
    "common_name": "American Boxwood",
    "care": {
      "Spring": "Thin outer growth to improve airflow.",
      "Summer": "Inspect for boxwood blight or leafminer.",
      "Fall": "Clean out interior dead leaves.",
      "Winter": "Tie up branches if heavy snow is forecast."
    }
  },
  {
    "common_name": "English Lavender",
    "care": {
      "Spring": "Prune back by one-third to prevent woodiness.",
      "Summer": "Harvest flowers for drying.",
      "Fall": "Ensure drainage is clear.",
      "Winter": "No specific care required."
    }
  },
  {
    "common_name": "Tulip",
    "care": {
      "Spring": "Enjoy blooms. Deadhead after flowering.",
      "Summer": "Allow foliage to yellow naturally.",
      "Fall": "Plant new bulbs.",
      "Winter": "Dormant."
    }
  },
  {
    "common_name": "Giant Hosta",
    "care": {
      "Spring": "Apply slug bait as leaves emerge.",
      "Summer": "Remove flower scapes if desired.",
      "Fall": "Cut back foliage after frost turns it mushy.",
      "Winter": "Dormant."
    }
  },
  {
    "common_name": "Kousa Dogwood",
    "care": {
      "Spring": "Monitor for anthracnose.",
      "Summer": "Mulch to keep roots cool.",
      "Fall": "Collect seeds if desired.",
      "Winter": "Prune for structure."
    }
  },
  {
    "common_name": "Maiden Grass",
    "care": {
      "Spring": "Cut back to 6 inches before new growth starts.",
      "Summer": "Fertilize lightly.",
      "Fall": "Leave plumes for winter interest.",
      "Winter": "Tie bundle to prevent flopping."
    }
  },
  {
    "common_name": "Coneflower",
    "care": {
      "Spring": "Divide clumps if crowded.",
      "Summer": "Deadhead for reblooming.",
      "Fall": "Leave seed heads for birds.",
      "Winter": "Cut back in late winter."
    }
  },
  {
    "common_name": "White Oak",
    "care": {
      "Spring": "Inspect for storm damage.",
      "Summer": "Monitor for oak wilt.",
      "Fall": "Rake leaves.",
      "Winter": "Structural pruning by arborist only."
    }
  },
  {
    "common_name": "Arborvitae",
    "care": {
      "Spring": "Shear lightly for shape.",
      "Summer": "Water deeply during drought.",
      "Fall": "Shake out inner dead needles.",
      "Winter": "Wrap to prevent deer damage."
    }
  },
  {
    "common_name": "Japanese Spurge",
    "care": {
      "Spring": "Mow high to thicken growth if leggy.",
      "Summer": "Monitor for scale.",
      "Fall": "Remove fallen tree leaves from bed.",
      "Winter": "Evergreen."
    }
  },
  {
    "common_name": "Catawba Rhododendron",
    "care": {
      "Spring": "Deadhead spent trusses carefully.",
      "Summer": "Ensure soil remains moist.",
      "Fall": "Apply antidesiccant spray.",
      "Winter": "Protect from winter sun."
    }
  },
  {
    "common_name": "Coral Bells",
    "care": {
      "Spring": "Remove winter-damaged leaves.",
      "Summer": "Watch for vine weevils.",
      "Fall": "Mulch to prevent frost heaving.",
      "Winter": "Check for heaving plugs."
    }
  }
]
EOF
chown ga:ga /home/ga/Documents/plant_database.json

# Ensure OpenOffice Writer desktop shortcut exists
mkdir -p /home/ga/Desktop
if [ -x "/opt/openoffice4/program/soffice" ]; then
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

# Record start state
date +%s > /tmp/task_start_time
echo "0" > /tmp/initial_file_size

# Take setup screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="