#!/bin/bash
set -e

echo "=== Setting up Accessible Water Report Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Create Documents directory and clean up
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/Oakwood_CCR_2024.odt 2>/dev/null || true
rm -f /home/ga/Documents/water_data.json 2>/dev/null || true
rm -f /home/ga/Documents/ph_levels_chart.png 2>/dev/null || true

# 2. Generate the JSON Data File
cat > /home/ga/Documents/water_data.json << 'EOF'
{
  "report_title": "City of Oakwood 2024 Consumer Confidence Report",
  "sections": [
    {
      "title": "Water Source",
      "content": "The City of Oakwood sources its water from the pristine Oakwood Aquifer. We perform daily testing to ensure safety and quality standards exceed state and federal regulations."
    },
    {
      "title": "Test Results",
      "content": "Our 2024 testing campaign revealed no violations. The chart below illustrates our stable pH levels throughout the year, maintaining an optimal balance for taste and pipe integrity."
    },
    {
      "title": "Health Information",
      "content": "Some people may be more vulnerable to contaminants in drinking water than the general population. Immuno-compromised persons should seek advice about drinking water from their health care providers."
    }
  ],
  "table_data": {
    "headers": ["Contaminant", "MCLG", "Detected Level", "Violation"],
    "rows": [
      ["Chlorine", "4 ppm", "0.8 ppm", "No"],
      ["Fluoride", "4 ppm", "0.9 ppm", "No"],
      ["Nitrate", "10 ppm", "1.2 ppm", "No"],
      ["Lead", "0 ppb", "2.1 ppb", "No"]
    ]
  },
  "image_alt_text": "Annual pH levels showing stability between 7.2 and 7.4",
  "document_properties_title": "2024 Water Quality Report"
}
EOF
chown ga:ga /home/ga/Documents/water_data.json

# 3. Generate a Dummy Chart Image (using Python)
# We create a simple PNG so the agent has something to insert.
python3 -c "
import matplotlib.pyplot as plt
import numpy as np

try:
    months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
    ph_levels = [7.2, 7.3, 7.25, 7.3, 7.35, 7.4, 7.38, 7.35, 7.3, 7.25, 7.22, 7.2]

    plt.figure(figsize=(6, 4))
    plt.plot(months, ph_levels, marker='o', color='blue')
    plt.title('2024 Average pH Levels')
    plt.ylabel('pH')
    plt.ylim(6.0, 8.5)
    plt.grid(True)
    plt.savefig('/home/ga/Documents/ph_levels_chart.png')
    print('Chart generated successfully.')
except ImportError:
    # Fallback if matplotlib not installed: create a solid color image
    from PIL import Image
    img = Image.new('RGB', (600, 400), color = (73, 109, 137))
    img.save('/home/ga/Documents/ph_levels_chart.png')
    print('Fallback image generated.')
" 2>/dev/null || true

# If python generation failed (missing libs), use convert (ImageMagick)
if [ ! -f "/home/ga/Documents/ph_levels_chart.png" ]; then
    echo "Generating fallback image with ImageMagick..."
    convert -size 600x400 xc:lightblue -fill black -draw "text 20,200 'pH Levels Chart'" /home/ga/Documents/ph_levels_chart.png 2>/dev/null || true
fi
chown ga:ga /home/ga/Documents/ph_levels_chart.png

# 4. Record Start Time and Initial State
date +%s > /tmp/task_start_time.txt
ls -la /home/ga/Documents > /tmp/initial_file_list.txt

# 5. Start OpenOffice Writer (Blank)
if ! pgrep -f "soffice" > /dev/null; then
    echo "Starting OpenOffice Writer..."
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenOffice Writer"; then
            break
        fi
        sleep 1
    done
fi

# Maximize Window
DISPLAY=:1 wmctrl -r "OpenOffice Writer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenOffice Writer" 2>/dev/null || true

# 6. Capture Initial Screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="