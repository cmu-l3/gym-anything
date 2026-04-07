#!/bin/bash
set -euo pipefail

echo "=== Setting up SEV-1 Post-Mortem Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create working directory and clean previous state
PRES_DIR="/home/ga/Documents/Presentations"
sudo -u ga mkdir -p "$PRES_DIR"
rm -f "$PRES_DIR/sev1_postmortem.pptx" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Generate the incident notes text file
cat > "$PRES_DIR/incident_notes.txt" << 'EOF'
INCIDENT POST-MORTEM NOTES
Title: SEV-1 US-East Network Partition
Date: 2024-10-27

Executive Summary:
A major network partition occurred in the US-East region, resulting in 45 minutes of complete downtime. Approximately 2.5 million API requests were dropped during this period.

Timeline (UTC):
14:02 - Automated alerts trigger for elevated error rates in US-East.
14:15 - SRE team declares SEV-1, engages network engineers.
14:32 - BGP route leak identified and isolated.
14:47 - Traffic normalizes, API success rate back to 99.99%.

Root Cause:
A misconfigured BGP route advertisement from a transit provider caused internal traffic to blackhole. The architecture diagram (us_east_architecture.png) shows the affected API Gateway.

Action Items:
- NET-1092: Implement stricter BGP route filtering on edge routers.
- SRE-4401: Add synthetic monitoring for cross-AZ network latency.
- SRE-4402: Update incident response runbook for routing anomalies.
EOF

# Generate the architecture diagram using ImageMagick
su - ga -c "convert -size 600x400 xc:white \
  -fill lightblue -draw 'rectangle 50,50 250,150' \
  -fill black -pointsize 20 -draw 'text 80,105 \"API Gateway\"' \
  -fill lightgreen -draw 'rectangle 350,50 550,150' \
  -fill black -pointsize 20 -draw 'text 380,105 \"App Servers\"' \
  -fill salmon -draw 'rectangle 200,250 400,350' \
  -fill black -pointsize 20 -draw 'text 230,305 \"Primary DB\"' \
  -stroke red -strokewidth 5 -draw 'line 250,100 350,100' \
  -stroke black -strokewidth 2 -draw 'line 150,150 300,250' \
  -stroke black -strokewidth 2 -draw 'line 450,150 300,250' \
  -stroke none -fill red -pointsize 24 -draw 'text 270,90 \"X (FAILED)\"' \
  $PRES_DIR/us_east_architecture.png"

# Set permissions
chown ga:ga "$PRES_DIR/incident_notes.txt"
chown ga:ga "$PRES_DIR/us_east_architecture.png"

# Kill any existing ONLYOFFICE instances
pkill -f "onlyoffice-desktopeditors" 2>/dev/null || true
sleep 2

# Launch ONLYOFFICE Presentation Editor
echo "Starting ONLYOFFICE Presentation Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors --new:slide > /tmp/onlyoffice_launch.log 2>&1 &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ONLYOFFICE"; then
        break
    fi
    sleep 1
done

# Maximize and focus ONLYOFFICE
DISPLAY=:1 wmctrl -r "ONLYOFFICE" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ONLYOFFICE" 2>/dev/null || true

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="