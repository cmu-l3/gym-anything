#!/bin/bash
echo "=== Setting up Sociology Sequence Analysis Task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Remove stale output files (Anti-gaming)
rm -f /home/ga/RProjects/output/career_clusters.csv
rm -f /home/ga/RProjects/output/state_durations.csv
rm -f /home/ga/RProjects/output/cluster_trajectories.png
rm -f /home/ga/RProjects/sequence_analysis.R

# Ensure TraMineR is NOT installed (Agent must install it)
# This tests package management skills
echo "Ensuring clean package state..."
R --vanilla --slave -e "if ('TraMineR' %in% installed.packages()) remove.packages('TraMineR')"

# Create starter R script
cat > /home/ga/RProjects/sequence_analysis.R << 'RSCRIPT'
# Sequence Analysis of MVAD Dataset
# Analysis of transition from school to work
#
# Requirements:
# 1. Install/Load TraMineR
# 2. Define sequence object (cols 17-86)
# 3. Optimal Matching (OM) distance (indel=1, sm=2)
# 4. Ward's Clustering (4 groups)
# 5. Outputs:
#    - career_clusters.csv (id, cluster)
#    - state_durations.csv (mean time in states by cluster)
#    - cluster_trajectories.png (state distribution plot)

# Write your code here...
RSCRIPT
chown ga:ga /home/ga/RProjects/sequence_analysis.R

# Record task start timestamp (Anti-gaming)
date +%s > /tmp/task_start_time

# Record initial state
echo '{"clusters_exists": false, "plot_exists": false}' > /tmp/initial_state.json

# Launch RStudio
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/sequence_analysis.R &"
    sleep 10
else
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/sequence_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
echo "Task: Sequence Analysis with TraMineR"