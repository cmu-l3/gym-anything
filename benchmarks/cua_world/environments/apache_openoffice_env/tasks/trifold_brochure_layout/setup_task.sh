#!/bin/bash
set -e
echo "=== Setting up Tri-fold Brochure Layout Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Create directory for assets
ASSETS_DIR="/home/ga/Documents/brochure_assets"
sudo -u ga mkdir -p "$ASSETS_DIR"

# 2. clean up previous runs
rm -f /home/ga/Documents/wellness_expo_brochure.odt 2>/dev/null || true

# 3. Create content text file
cat > "$ASSETS_DIR/content.txt" << 'EOF'
SPRING 2026 WELLNESS EXPO
"Your Path to a Healthier Life"

Hosted by: Mercy General Health System
Date: Saturday, May 16, 2026
Time: 9:00 AM – 2:00 PM
Location: River Valley Community Center, 4500 Maple Ave.

ABOUT THE EVENT
Join us for a day dedicated to your well-being! The Wellness Expo brings together local health professionals, fitness experts, and community organizations to provide free resources and screenings to the public. Admission is free and open to all ages.

FREE SERVICES
- Blood Pressure & BMI Screenings
- Cholesterol & Glucose Checks (Fasting required)
- Vision & Hearing Tests
- Mental Health Consultations
- Nutrition Planning Workshops

EVENT SCHEDULE
9:30 AM  - Morning Yoga on the Lawn
10:30 AM - "Heart Health 101" Seminar
11:30 AM - Healthy Cooking Demonstration
1:00 PM  - Raffle Prize Drawing

CONTACT US
For more information or to volunteer:
Phone: (555) 019-2834
Email: outreach@mercygeneral.org
Web: www.mercygeneral.org/expo2026
EOF
chown ga:ga "$ASSETS_DIR/content.txt"

# 4. Generate asset images using ImageMagick (safer than downloading)
# Logo: Green circle on transparent background
convert -size 200x200 xc:transparent -fill "#2E8B57" -draw "circle 100,100 100,20" \
    -fill white -pointsize 24 -gravity center -annotate +0+0 "MERCY" \
    "$ASSETS_DIR/wellness_logo.png"

# Activity Photo: Blue placeholder photo
convert -size 400x300 xc:lightblue -fill "#4682B4" -draw "rectangle 0,150 400,300" \
    -fill white -pointsize 30 -gravity center -annotate +0-50 "Yoga Session" \
    "$ASSETS_DIR/photo_activity.jpg"

chown ga:ga "$ASSETS_DIR/wellness_logo.png"
chown ga:ga "$ASSETS_DIR/photo_activity.jpg"

# 5. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 6. Ensure OpenOffice is ready (but don't launch it, let agent do it)
# We just ensure the environment is clean and desktop shortcut exists
if [ -f "/usr/share/applications/openoffice4-writer.desktop" ]; then
    cp "/usr/share/applications/openoffice4-writer.desktop" "/home/ga/Desktop/"
    chmod +x "/home/ga/Desktop/openoffice4-writer.desktop"
    chown ga:ga "/home/ga/Desktop/openoffice4-writer.desktop"
fi

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Assets created in $ASSETS_DIR"