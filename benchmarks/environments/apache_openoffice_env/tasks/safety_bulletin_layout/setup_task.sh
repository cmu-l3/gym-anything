#!/bin/bash
set -e
echo "=== Setting up Safety Bulletin Layout Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Create Directories
sudo -u ga mkdir -p /home/ga/Documents/assets

# 2. Clear previous attempts
rm -f /home/ga/Documents/Winter_Safety_Alert.odt 2>/dev/null || true
rm -f /home/ga/Documents/safety_draft.txt 2>/dev/null || true
rm -f /home/ga/Documents/assets/* 2>/dev/null || true

# 3. Create Draft Text
cat > /home/ga/Documents/safety_draft.txt << 'EOF'
SITE SAFETY ALERT
Winter Weather Hazards

The upcoming forecast predicts severe cold and potential icing conditions across all tri-state job sites. Site supervisors must ensure all crews are briefed on the following hazards.

COLD STRESS
Prolonged exposure to freezing temperatures can lead to frostbite and hypothermia. Workers should dress in layers and take frequent breaks in heated shelters. Monitor peers for signs of confusion, slurred speech, or shivering.

SLIPS AND FALLS
Ice accumulation on scaffolding, ladders, and walkways poses a critical risk. All walkways must be salted and cleared before shift start. Traction aids (ice cleats) are mandatory for all personnel working on grade.

VEHICLE OPERATIONS
Black ice is likely on site access roads. Reduce speed to 5 MPH. Ensure all heavy machinery has been warmed up properly before operation to prevent hydraulic failure.

IMMEDIATE ACTION REQUIRED:
Any work on elevated platforms (above 6ft) is SUSPENDED if wind speeds exceed 20mph or if surfaces are iced over. Do not attempt to de-ice elevated steel without fall protection.

Key Precautions:
Inspect all heaters for proper ventilation to prevent CO buildup.
Cover materials that are susceptible to freeze damage.
Report any slip hazards to the Safety Officer immediately.
Keep hydration fluids available; dehydration increases susceptibility to cold.

Summit Construction Group - Safety Department
EOF
chown ga:ga /home/ga/Documents/safety_draft.txt

# 4. Create Dummy Images (using python to generate valid image files without internet)
# This ensures the task is self-contained and doesn't fail on network issues.
python3 -c "
import random
def create_ppm(filename, width, height, color):
    with open(filename, 'wb') as f:
        f.write(f'P6\n{width} {height}\n255\n'.encode())
        for _ in range(height):
            for _ in range(width):
                f.write(bytes(color))

# Hazard photo (Gray/Blueish for 'winter')
create_ppm('/home/ga/Documents/assets/hazard_photo.ppm', 400, 300, [100, 100, 150])
# Warning icon (Red/Yellow)
create_ppm('/home/ga/Documents/assets/warning_icon.ppm', 100, 100, [255, 200, 0])
"

# Convert PPM to JPG/PNG if ImageMagick is available, otherwise rename (OpenOffice handles PPM usually, but lets try to be standard)
# If convert is not present, we leave as PPM or try to use python PIL if available.
# Given the environment, we'll try to just rename them to .jpg/.png as simple headers might pass, 
# but to be safe, we will just leave them as image files OpenOffice can open.
# The previous step generated raw PPM P6 binary format which OpenOffice supports.
mv /home/ga/Documents/assets/hazard_photo.ppm /home/ga/Documents/assets/hazard_photo.jpg
mv /home/ga/Documents/assets/warning_icon.ppm /home/ga/Documents/assets/warning_icon.png
chown -R ga:ga /home/ga/Documents/assets

# 5. Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_file_exists

# 6. Launch OpenOffice Writer
echo "Launching OpenOffice Writer..."
if ! pgrep -f "soffice" > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
    
    # Wait for window
    for i in {1..30}; do
        if wmctrl -l | grep -i "OpenOffice Writer"; then
            break
        fi
        sleep 1
    done
fi

# Maximize window
WID=$(wmctrl -l | grep -i "OpenOffice Writer" | awk '{print $1}' | head -n 1)
if [ -n "$WID" ]; then
    wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
    wmctrl -i -a "$WID"
fi

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="