#!/bin/bash
echo "=== Setting up Hazardous Gas Evolution Profiling Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Desktop directory exists
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Create the scenarios file on the Desktop
cat > /home/ga/Desktop/mixing_scenarios.txt << 'EOF'
HAZARDOUS MIXING SCENARIOS FOR SENSOR SELECTION
===============================================

Instructions:
For each Area, use CAMEO Chemicals Reactivity Tool to mix Chemical A and Chemical B.
Identify the specific gas byproduct mentioned in the hazard predictions (e.g., "Generates ...").

| Area   | Chemical A (Tank)      | Chemical B (Contaminant) |
|--------|------------------------|--------------------------|
| Area 1 | Sodium Hypochlorite    | Ammonia                  |
| Area 2 | Sodium Cyanide         | Sulfuric Acid            |
| Area 3 | Sodium Sulfide         | Formic Acid              |
| Area 4 | Zinc Powder            | Hydrochloric Acid        |
| Area 5 | Sodium Bisulfite       | Nitric Acid              |

Output Requirement:
Create a CSV file at ~/Desktop/sensor_selection_report.csv with headers:
Area,Chemical_A,Chemical_B,Evolved_Gas_Name
EOF

chown ga:ga /home/ga/Desktop/mixing_scenarios.txt

# Remove any existing result file
rm -f /home/ga/Desktop/sensor_selection_report.csv

# Launch Firefox to CAMEO Chemicals
# We use the MyChemicals page directly if possible, or just the homepage
launch_firefox_to_url "https://cameochemicals.noaa.gov/reactivity" ga

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="