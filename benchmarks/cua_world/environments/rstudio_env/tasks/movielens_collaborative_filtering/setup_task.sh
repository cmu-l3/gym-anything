#!/bin/bash
echo "=== Setting up MovieLens Recommender Task ==="

source /workspace/scripts/task_utils.sh

# Set up directories
mkdir -p /home/ga/RProjects/output
mkdir -p /home/ga/RProjects/datasets
chown -R ga:ga /home/ga/RProjects

# Clean up any previous runs
rm -f /home/ga/RProjects/output/*
rm -f /tmp/task_result.json
rm -f /home/ga/RProjects/movielens_recommender.R

# Create starter script
cat > /home/ga/RProjects/movielens_recommender.R << 'RSCRIPT'
# MovieLens 100k Collaborative Filtering Recommender
#
# Task requirements:
# 1. Download and unzip MovieLens 100k from https://files.grouplens.org/datasets/movielens/ml-100k.zip
# 2. Install and load the 'recommenderlab' package
# 3. Load u.data and convert to a realRatingMatrix
# 4. Save matrix summary (n_users, n_items) to output/matrix_summary.csv
# 5. Save rating distribution plot to output/rating_distribution.png
# 6. Split data 80/20 and evaluate UBCF and IBCF models
# 7. Save evaluation results (RMSE, MAE) to output/model_evaluation.csv
# 8. Train a UBCF model on all data and predict Top 10 for User 42
# 9. Load u.item to get movie titles and join with recommendations
#    (Hint: u.item is pipe-separated '|' and may require quote="")
# 10. Save Top 10 recommendations to output/user_42_recommendations.csv

# Write your code below:

RSCRIPT
chown ga:ga /home/ga/RProjects/movielens_recommender.R

# Record precise start timestamp for anti-gaming (AFTER creating starter files)
date +%s > /tmp/task_start_ts

# Ensure RStudio is running and load the script
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/movielens_recommender.R > /dev/null 2>&1 &"
    sleep 10
else
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/movielens_recommender.R > /dev/null 2>&1 &"
    sleep 3
fi

# Configure window
focus_rstudio
maximize_rstudio
sleep 2

# Take initial proof screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="