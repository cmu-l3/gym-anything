#!/bin/bash
echo "=== Setting up phylogenetics_woodmouse_evolution task ==="

# Source utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
else
    # Fallback functions
    take_screenshot() { DISPLAY=:1 scrot "$1" 2>/dev/null || true; }
    is_rstudio_running() { pgrep -f "rstudio" > /dev/null 2>&1; }
    focus_rstudio() { WID=$(DISPLAY=:1 wmctrl -l | grep -i "rstudio" | head -1 | awk '{print $1}'); [ -n "$WID" ] && DISPLAY=:1 wmctrl -i -a "$WID"; }
    maximize_rstudio() { WID=$(DISPLAY=:1 wmctrl -l | grep -i "rstudio" | head -1 | awk '{print $1}'); [ -n "$WID" ] && DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz; }
fi

# Create working directories
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects

# Remove any stale files (anti-gaming)
rm -f /home/ga/RProjects/output/woodmouse_dist.csv
rm -f /home/ga/RProjects/output/woodmouse_tree.nwk
rm -f /home/ga/RProjects/output/woodmouse_tree_plot.png

# Create starter R script BEFORE recording timestamp
cat > /home/ga/RProjects/woodmouse_phylogeny.R << 'RSCRIPT'
# Woodmouse Phylogenetic Analysis
# Dataset: ape::woodmouse
# Task: Distance matrix (K80), NJ tree, Rooting (No305), Bootstrapping (100 reps)

# Write your code below:

RSCRIPT
chown ga:ga /home/ga/RProjects/woodmouse_phylogeny.R

# Record task start timestamp (Starter script mtime will be < TASK_START)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Ensure RStudio is running and load the script
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/woodmouse_phylogeny.R &"
    sleep 8
else
    # Open the target script if RStudio is already open
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/woodmouse_phylogeny.R &" 2>/dev/null || true
    sleep 3
fi

# Focus and maximize RStudio window
focus_rstudio
sleep 1
maximize_rstudio
sleep 1

# Capture initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Target script: /home/ga/RProjects/woodmouse_phylogeny.R"