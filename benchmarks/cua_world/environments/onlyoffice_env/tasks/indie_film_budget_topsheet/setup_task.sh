#!/bin/bash
echo "=== Setting up Indie Film Budget Task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/Documents/Spreadsheets

# Create the Python script to generate the deterministic dataset
cat > /tmp/generate_budget.py << 'EOF'
import csv
import sys
import os

output_path = sys.argv[1]
os.makedirs(os.path.dirname(output_path), exist_ok=True)

data = [
    ("Acct_Code", "Category", "Description", "Expense_Type", "Base_Cost"),
    (1100, "Above-the-Line", "Story Rights", "Non-Labor", 50000),
    (1101, "Above-the-Line", "Screenwriter", "Labor", 85000),
    (1200, "Above-the-Line", "Executive Producer", "Labor", 100000),
    (1201, "Above-the-Line", "Line Producer", "Labor", 65000),
    (1300, "Above-the-Line", "Director", "Labor", 120000),
    (1400, "Above-the-Line", "Lead Actor 1", "Labor", 150000),
    (1401, "Above-the-Line", "Lead Actor 2", "Labor", 150000),
    (1402, "Above-the-Line", "Supporting Cast", "Labor", 80000),
    (1403, "Above-the-Line", "Day Players", "Labor", 45000),
    (1404, "Above-the-Line", "Casting Director", "Labor", 25000),
    (1405, "Above-the-Line", "Cast Travel & Living", "Non-Labor", 35000),
    (2000, "Below-the-Line", "Unit Production Manager", "Labor", 40000),
    (2001, "Below-the-Line", "First Assistant Director", "Labor", 35000),
    (2002, "Below-the-Line", "Second Assistant Director", "Labor", 25000),
    (2003, "Below-the-Line", "Production Coordinator", "Labor", 20000),
    (2100, "Below-the-Line", "Director of Photography", "Labor", 60000),
    (2101, "Below-the-Line", "Camera Operator", "Labor", 25000),
    (2102, "Below-the-Line", "1st Assistant Camera", "Labor", 20000),
    (2103, "Below-the-Line", "2nd Assistant Camera", "Labor", 15000),
    (2104, "Below-the-Line", "Camera Equipment Rental", "Non-Labor", 85000),
    (2200, "Below-the-Line", "Gaffer", "Labor", 30000),
    (2201, "Below-the-Line", "Best Boy Electric", "Labor", 22000),
    (2202, "Below-the-Line", "Lighting Equipment", "Non-Labor", 45000),
    (2300, "Below-the-Line", "Key Grip", "Labor", 30000),
    (2301, "Below-the-Line", "Best Boy Grip", "Labor", 22000),
    (2302, "Below-the-Line", "Grip Equipment", "Non-Labor", 35000),
    (2400, "Below-the-Line", "Production Designer", "Labor", 50000),
    (2401, "Below-the-Line", "Art Director", "Labor", 35000),
    (2402, "Below-the-Line", "Set Decorator", "Labor", 25000),
    (2403, "Below-the-Line", "Set Construction Materials", "Non-Labor", 65000),
    (2404, "Below-the-Line", "Props Purchases", "Non-Labor", 30000),
    (2500, "Below-the-Line", "Location Manager", "Labor", 25000),
    (2501, "Below-the-Line", "Location Site Fees", "Non-Labor", 80000),
    (2502, "Below-the-Line", "Location Security", "Labor", 15000),
    (2600, "Below-the-Line", "Costume Designer", "Labor", 35000),
    (2601, "Below-the-Line", "Wardrobe Supervisor", "Labor", 20000),
    (2602, "Below-the-Line", "Wardrobe Purchases", "Non-Labor", 25000),
    (2700, "Below-the-Line", "Production Sound Mixer", "Labor", 28000),
    (2701, "Below-the-Line", "Boom Operator", "Labor", 18000),
    (2702, "Below-the-Line", "Sound Equipment Rental", "Non-Labor", 12000),
    (2800, "Below-the-Line", "Key Makeup Artist", "Labor", 25000),
    (2801, "Below-the-Line", "Key Hair Stylist", "Labor", 25000),
    (2802, "Below-the-Line", "Makeup/Hair Supplies", "Non-Labor", 8000),
    (2900, "Below-the-Line", "Catering", "Non-Labor", 35000),
    (2901, "Below-the-Line", "Craft Service", "Non-Labor", 15000),
    (2902, "Below-the-Line", "Transportation Coordinator", "Labor", 22000),
    (2903, "Below-the-Line", "Vehicle Rentals", "Non-Labor", 40000),
    (2904, "Below-the-Line", "Production Insurance", "Non-Labor", 35000),
    (3000, "Post-Production", "Editor", "Labor", 60000),
    (3001, "Post-Production", "Assistant Editor", "Labor", 25000),
    (3002, "Post-Production", "Editing Facility Rental", "Non-Labor", 15000),
    (3100, "Post-Production", "Supervising Sound Editor", "Labor", 35000),
    (3101, "Post-Production", "Foley Artist", "Labor", 15000),
    (3102, "Post-Production", "ADR Recording", "Non-Labor", 8000),
    (3103, "Post-Production", "Sound Mixing Facility", "Non-Labor", 25000),
    (3200, "Post-Production", "Composer", "Labor", 40000),
    (3201, "Post-Production", "Music Licensing", "Non-Labor", 50000),
    (3300, "Post-Production", "Colorist", "Labor", 20000),
    (3301, "Post-Production", "DI Facility", "Non-Labor", 15000),
    (3302, "Post-Production", "VFX Supervisor", "Labor", 45000),
    (3303, "Post-Production", "VFX Shot Production", "Non-Labor", 85000),
    (3400, "Post-Production", "Deliverables", "Non-Labor", 25000),
    (3401, "Post-Production", "Legal & Accounting", "Non-Labor", 40000)
]

with open(output_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(data)
EOF

python3 /tmp/generate_budget.py /home/ga/Documents/Spreadsheets/indie_feature_raw.csv
chown -R ga:ga /home/ga/Documents/Spreadsheets

# Clean up old ONLYOFFICE instances
pkill -f "onlyoffice-desktopeditors" || true
sleep 2

# Start ONLYOFFICE with the raw CSV
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors /home/ga/Documents/Spreadsheets/indie_feature_raw.csv &"

# Wait for ONLYOFFICE window to appear
echo "Waiting for ONLYOFFICE..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "indie_feature_raw\|onlyoffice"; then
        break
    fi
    sleep 1
done
sleep 5

# Maximize and focus
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ONLYOFFICE" 2>/dev/null || true

# Capture initial screenshot
sleep 2
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="