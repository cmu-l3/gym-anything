#!/bin/bash
echo "=== Setting up Protein Structure NMA Task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Ensure bio3d is NOT installed (to force agent to install it)
echo "Ensuring bio3d is clean..."
R --vanilla --slave -e "if('bio3d' %in% rownames(installed.packages())) remove.packages('bio3d')" 2>/dev/null || true

# Create starter R script
cat > /home/ga/RProjects/nma_analysis.R << 'EOF'
# Normal Mode Analysis of Adenylate Kinase (1AKE)
# Using bio3d package

# 1. Install and load bio3d
# ...

# 2. Fetch PDB
# ...

# 3. NMA and Fluctuation Analysis (Mode 7)
# ...

# 4. Save Outputs
# ...
EOF
chown ga:ga /home/ga/RProjects/nma_analysis.R

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Record initial state
echo '{"csv_exists": false, "plot_exists": false, "pdb_exists": false}' > /tmp/initial_state.json

# Start RStudio
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/nma_analysis.R &"
    sleep 10
else
    # Just open the file
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/nma_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="