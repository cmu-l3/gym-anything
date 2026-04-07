#!/bin/bash
echo "=== Setting up digitize_legacy_entry task ==="

source /workspace/scripts/task_utils.sh

# 1. Generate Random Data
DATES=("2024-02-10" "2024-03-15" "2024-01-20" "2024-04-05" "2023-11-28" "2023-12-12")
TITLES=("Protein Stability Test" "Western Blot Optimization" "HeLa Cell Passaging" "Antibody Titration" "PCR Amplification" "ELISA Calibration")
NOTES=("Precipitation observed in tube 3" "High background signal on film" "Control group showed no growth" "Incubator temp fluctuated +2C" "Gel showed primer dimers" "Standard curve R2=0.99")

RAND_DATE=${DATES[$RANDOM % ${#DATES[@]}]}
RAND_TITLE=${TITLES[$RANDOM % ${#TITLES[@]}]}
RAND_NOTE=${NOTES[$RANDOM % ${#NOTES[@]}]}

cat > /tmp/ground_truth.json <<EOF
{
  "date": "$RAND_DATE",
  "title": "$RAND_TITLE",
  "note": "$RAND_NOTE",
  "expected_task_name": "$RAND_DATE - $RAND_TITLE"
}
EOF

# 2. Use ImageMagick to draw text as a "Scan"
echo "Generating scanned document..."
convert -size 600x800 xc:white \
    -pointsize 24 -fill black \
    -draw "text 50,80 'Lab Notebook: J. Doe'" \
    -draw "text 50,150 'Date: $RAND_DATE'" \
    -draw "text 50,220 'Experiment: $RAND_TITLE'" \
    -draw "text 50,350 'Observations:'" \
    -draw "text 70,400 '$RAND_NOTE'" \
    -stroke black -strokewidth 2 -draw "line 50,100 550,100" \
    /home/ga/Desktop/notebook_scan.jpg

chown ga:ga /home/ga/Desktop/notebook_scan.jpg
chmod 644 /home/ga/Desktop/notebook_scan.jpg

# 3. Create the "Legacy Archive" Project
echo "Creating Legacy Archive project via Rails..."
scinote_rails_query "
User.current = User.find_by(email: 'admin@scinote.net')
team = Team.first
unless Project.where(name: 'Legacy Archive').exists?
  p = Project.create!(name: 'Legacy Archive', team: team, creator: User.current)
  Experiment.create!(name: 'Batch 1 Digitization', project: p, creator: User.current)
  puts 'Project and Experiment created'
end
"

# 4. Start Firefox and take screenshot
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="