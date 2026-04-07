#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Museum Exhibition Pitch Deck Task ==="

# Record task start timestamp for anti-gaming verification
echo $(date +%s) > /tmp/task_start_time.txt

# Clean any existing ONLYOFFICE instances
kill_onlyoffice ga
cleanup_temp_files
sleep 1

ASSETS_DIR="/home/ga/Documents/Presentations/exhibition_assets"
sudo -u ga mkdir -p "$ASSETS_DIR"

echo "Downloading real exhibition image assets..."

# Download real public domain historical images from Wikimedia Commons
sudo -u ga wget -q -O "$ASSETS_DIR/artifact_1_telegraph.jpg" "https://upload.wikimedia.org/wikipedia/commons/thumb/e/e0/Telegraph_key_1.jpg/800px-Telegraph_key_1.jpg" || convert -size 800x600 xc:gray -gravity center -pointsize 40 -annotate 0 "Telegraph Key" "$ASSETS_DIR/artifact_1_telegraph.jpg"
sudo -u ga wget -q -O "$ASSETS_DIR/artifact_2_golden_spike.jpg" "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/Golden_Spike.jpg/800px-Golden_Spike.jpg" || convert -size 800x600 xc:gold -gravity center -pointsize 40 -annotate 0 "Golden Spike" "$ASSETS_DIR/artifact_2_golden_spike.jpg"
sudo -u ga wget -q -O "$ASSETS_DIR/artifact_3_workers.jpg" "https://upload.wikimedia.org/wikipedia/commons/thumb/3/36/Central_Pacific_Railroad_Chinese_workers.jpg/800px-Central_Pacific_Railroad_Chinese_workers.jpg" || convert -size 800x600 xc:sepia -gravity center -pointsize 40 -annotate 0 "Railroad Workers" "$ASSETS_DIR/artifact_3_workers.jpg"
sudo -u ga wget -q -O "$ASSETS_DIR/artifact_4_map.jpg" "https://upload.wikimedia.org/wikipedia/commons/thumb/c/c5/First_Transcontinental_Railroad_route_map.png/800px-First_Transcontinental_Railroad_route_map.png" || convert -size 800x600 xc:white -gravity center -pointsize 40 -annotate 0 "Transcontinental Map" "$ASSETS_DIR/artifact_4_map.jpg"
sudo -u ga wget -q -O "$ASSETS_DIR/gallery_floorplan.png" "https://upload.wikimedia.org/wikipedia/commons/thumb/b/b3/Floor_plan_of_the_National_Museum_of_Korea.svg/800px-Floor_plan_of_the_National_Museum_of_Korea.svg.png" || convert -size 800x600 xc:lightblue -gravity center -pointsize 40 -annotate 0 "Gallery Floorplan" "$ASSETS_DIR/gallery_floorplan.png"

# Create the curatorial master text document
cat > "$ASSETS_DIR/curatorial_master_text.txt" << 'EOF'
Exhibition Proposal: The Iron Web: Rails and Telegraphs
Fall 2026

=============================
Slide 1: Title Slide
=============================
Title: The Iron Web: Rails and Telegraphs
Subtitle: Fall 2026 Exhibition Proposal
SPEAKER NOTE (Add to notes panel): Acknowledge the Miller Foundation for preliminary funding.

=============================
Slide 2: Exhibition Overview
=============================
- Explore the synergistic growth of railroads and telegraph networks.
- Highlight the stories of diverse workers who built the infrastructure.
- Examine the economic and cultural impact of instant communication and rapid transit.

=============================
Slide 3: Artifact 1 - 1860 Morse Telegraph Key
=============================
- Provenance: Donated by the Western Union Historical Archive
- Description: Standard issue key used across the transcontinental telegraph line.

=============================
Slide 4: Artifact 2 - The Golden Spike
=============================
- Provenance: On loan from Stanford University
- Description: Ceremonial final spike driven by Leland Stanford at Promontory Summit, 1869.

=============================
Slide 5: Artifact 3 - Railroad Workers
=============================
- Provenance: Historical Society Photography Collection
- Description: Chinese laborers constructing the Central Pacific Railroad through the Sierra Nevada.

=============================
Slide 6: Artifact 4 - 1870 Transcontinental Map
=============================
- Provenance: Library of Congress Maps Division
- Description: Early cartographic representation of the completed continuous rail line.

=============================
Slide 7: Proposed Floor Plan
=============================
- Insert the gallery_floorplan.png image showing the sequential journey through the exhibition.

=============================
Slide 8: Budget Breakdown
=============================
Create a 4-row x 2-column table with the following:
Curation     $45,000
Fabrication  $85,000
Marketing    $20,000
Total        $150,000
EOF

chown -R ga:ga "$ASSETS_DIR"

# Launch ONLYOFFICE Presentation Editor with a blank slide
echo "Launching ONLYOFFICE Presentation Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors --new:slide > /tmp/onlyoffice_launch.log 2>&1 &"
sleep 5

# Wait for ONLYOFFICE window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ONLYOFFICE"; then
        echo "ONLYOFFICE window detected."
        break
    fi
    sleep 1
done

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "ONLYOFFICE" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ONLYOFFICE" 2>/dev/null || true
sleep 2

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="