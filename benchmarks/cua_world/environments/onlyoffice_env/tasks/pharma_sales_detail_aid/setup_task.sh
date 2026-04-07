#!/bin/bash
echo "=== Setting up Pharma Sales Detail Aid task ==="

source /workspace/scripts/task_utils.sh || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any previous runs
pkill -f "onlyoffice-desktopeditors" 2>/dev/null || true
sleep 1

# Setup workspace
WORKSPACE="/home/ga/Documents/Presentations"
sudo -u ga mkdir -p "$WORKSPACE"
rm -f "$WORKSPACE/cardio_detail_aid.pptx" 2>/dev/null || true

# 1. Create FDA Label Copy Text
cat > "$WORKSPACE/fda_label_copy.txt" << 'EOF'
Indication: For the treatment of hyperlipidemia

Mechanism of Action: Rosuvastatin is a selective and competitive inhibitor of HMG-CoA reductase, the rate-limiting enzyme that converts 3-hydroxy-3-methylglutaryl coenzyme A to mevalonate, a precursor of cholesterol.

Dosing & Administration: Dose range: 5 to 40 mg once daily. Use 40 mg dose only for patients not reaching LDL-C goal with 20 mg.

Contraindications: Known hypersensitivity to product components. Active liver disease, which may include unexplained persistent elevations in hepatic transaminase levels. Pregnancy and lactation.
EOF
chown ga:ga "$WORKSPACE/fda_label_copy.txt"

# 2. Create Adverse Events CSV
cat > "$WORKSPACE/adverse_events.csv" << 'EOF'
Adverse Event,Rosuvastatin %,Placebo %
Myalgia,3.1,2.0
Asthenia,2.5,1.6
Headache,5.5,5.0
EOF
chown ga:ga "$WORKSPACE/adverse_events.csv"

# 3. Create Efficacy Chart (using ImageMagick to draw a realistic clinical line chart)
convert -size 600x400 xc:white -fill white -stroke black -draw "line 50,350 550,350 line 50,50 50,350" \
    -stroke red -strokewidth 3 -draw "polyline 50,350 150,340 250,320 350,280 450,230 550,150" \
    -stroke blue -strokewidth 3 -draw "polyline 50,350 150,345 250,335 350,320 450,300 550,270" \
    -fill black -stroke none -pointsize 20 -draw "text 120,30 'JUPITER Trial: Rosuvastatin vs Placebo'" \
    -pointsize 14 -draw "text 60,140 'Placebo'" -draw "text 60,260 'Rosuvastatin'" \
    "$WORKSPACE/efficacy_chart.png"
chown ga:ga "$WORKSPACE/efficacy_chart.png"

# Launch ONLYOFFICE Presentation Editor
echo "Starting ONLYOFFICE Presentation Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors --new:slide > /tmp/onlyoffice.log 2>&1 &"

# Wait for application window to appear
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

# Take initial state screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="