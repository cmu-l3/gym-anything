#!/bin/bash
# Setup script for travel_itinerary_layout task

echo "=== Setting up Travel Itinerary Layout Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Create directories
sudo -u ga mkdir -p /home/ga/Documents/images

# 2. Clean up previous artifacts
rm -f /home/ga/Documents/Italy_Proposal_2025.odt 2>/dev/null || true
rm -f /home/ga/Documents/tour_data.json 2>/dev/null || true
rm -f /home/ga/Documents/images/* 2>/dev/null || true

# 3. Create JSON Data File
cat > /home/ga/Documents/tour_data.json << 'EOF'
{
  "tour_title": "Italian Renaissance Tour",
  "client_name": "Mr. & Mrs. Sterling",
  "dates": "September 10-17, 2025",
  "itinerary": [
    {
      "day": "Day 1: Arrival in Rome",
      "activity": "Private transfer to hotel. Evening welcome dinner at La Pergola.",
      "hotel": "Hotel de Russie, Rome"
    },
    {
      "day": "Day 2: Imperial Rome",
      "activity": "VIP access to the Colosseum and Roman Forum. Private guide for the Pantheon.",
      "hotel": "Hotel de Russie, Rome"
    },
    {
      "day": "Day 3: The Vatican",
      "activity": "Early morning private viewing of the Sistine Chapel and Vatican Museums.",
      "hotel": "Hotel de Russie, Rome"
    },
    {
      "day": "Day 4: Transfer to Florence",
      "activity": "High-speed train to Florence. Sunset wine tasting in Chianti.",
      "hotel": "Four Seasons Hotel Firenze"
    },
    {
      "day": "Day 5: Renaissance Art",
      "activity": "Guided tour of the Uffizi Gallery and Accademia to see David.",
      "hotel": "Four Seasons Hotel Firenze"
    },
    {
      "day": "Day 6: Venice via Ferrari",
      "activity": "Drive a Ferrari to Venice. Private gondola ride at sunset.",
      "hotel": "Hotel Danieli, Venice"
    },
    {
      "day": "Day 7: Departure",
      "activity": "Private water taxi to Marco Polo Airport.",
      "hotel": "N/A"
    }
  ]
}
EOF
chown ga:ga /home/ga/Documents/tour_data.json

# 4. Generate Placeholder Images (using Python to ensure they are valid image files)
# We create simple solid color images with text logic is too complex without PIL,
# so we generate minimal valid PPM/PNG files.
python3 << 'PYEOF'
import os

def create_dummy_image(filename, color_rgb):
    # Create a simple P3 PPM image
    width, height = 400, 300
    header = f"P3\n{width} {height}\n255\n"
    pixel = f"{color_rgb[0]} {color_rgb[1]} {color_rgb[2]} "
    data = header + (pixel * (width * height))
    
    # Convert to binary for writing (PPM P3 is text based actually, but let's assume we want .jpg extension for the agent)
    # OpenOffice handles renamed PPMs or we can just make them .ppm. 
    # Better: Use minimal uncompressed PNG header if possible, but that's hard.
    # We will assume 'convert' is installed from the base install_openoffice.sh (imagemagick/graphicsmagick).
    # If not, we rely on the environment having typical linux tools. 
    # Setup script 'install_openoffice.sh' installs 'scrot' which often pulls deps, but let's be safe.
    # We will write text files and try to use 'convert' if available, otherwise just leave them as dummy files 
    # that OpenOffice might complain about but show a placeholder, or use a tiny valid binary bitmap.
    
    # Actually, let's just make valid BMPs. It's easier to write binary BMP structure.
    # Minimal 1x1 BMP
    # But we want 400x300. 
    
    with open(filename, 'wb') as f:
        # BMP Header (14 bytes) + DIB Header (40 bytes) for a 1x1 pixel red image
        # This is too complex to script reliably without PIL.
        # Fallback: Create text files? No, agent needs to insert images.
        pass

# Let's use ImageMagick 'convert' if available (installed in install_openoffice.sh via build-essential or deps usually).
# If not, we try to download dummy images.

os.makedirs("/home/ga/Documents/images", exist_ok=True)
PYEOF

# Check for convert
if command -v convert >/dev/null 2>&1; then
    convert -size 640x480 xc:red -gravity center -pointsize 24 -annotate 0 "Rome Colosseum" /home/ga/Documents/images/rome_colosseum.jpg
    convert -size 640x480 xc:green -gravity center -pointsize 24 -annotate 0 "Florence Duomo" /home/ga/Documents/images/florence_duomo.jpg
    convert -size 640x480 xc:blue -gravity center -pointsize 24 -annotate 0 "Venice Canal" /home/ga/Documents/images/venice_canal.jpg
    convert -size 200x100 xc:orange -gravity center -pointsize 20 -annotate 0 "Global Horizons" /home/ga/Documents/images/logo.png
else
    # Fallback: simple colored PPM files renamed to jpg (OpenOffice often handles this or shows placeholder)
    # Create a red rect
    echo "P3 100 100 255 $(for i in {1..10000}; do echo "255 0 0 "; done)" > /home/ga/Documents/images/rome_colosseum.ppm
    mv /home/ga/Documents/images/rome_colosseum.ppm /home/ga/Documents/images/rome_colosseum.jpg
    
    echo "P3 100 100 255 $(for i in {1..10000}; do echo "0 255 0 "; done)" > /home/ga/Documents/images/florence_duomo.ppm
    mv /home/ga/Documents/images/florence_duomo.ppm /home/ga/Documents/images/florence_duomo.jpg
    
    echo "P3 100 100 255 $(for i in {1..10000}; do echo "0 0 255 "; done)" > /home/ga/Documents/images/venice_canal.ppm
    mv /home/ga/Documents/images/venice_canal.ppm /home/ga/Documents/images/venice_canal.jpg

    echo "P3 50 50 255 $(for i in {1..2500}; do echo "255 165 0 "; done)" > /home/ga/Documents/images/logo.ppm
    mv /home/ga/Documents/images/logo.ppm /home/ga/Documents/images/logo.png
fi

chown -R ga:ga /home/ga/Documents/images

# 5. Launch OpenOffice Writer (Clean Slate)
pkill -f soffice 2>/dev/null || true
sleep 1

echo "Launching OpenOffice Writer..."
su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"

# 6. Wait for it to appear
wait_for_window "OpenOffice Writer" 30

# 7. Maximize
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 8. Record Start Time
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_file_exists

# 9. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="