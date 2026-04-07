#!/bin/bash
echo "=== Setting up Clothing Reviews Sentiment Task ==="

source /workspace/scripts/task_utils.sh

# Create directories
mkdir -p /home/ga/RProjects/datasets
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time

# 1. Prepare Reviews Dataset
# Using a stable raw URL for the dataset
REVIEWS_PATH="/home/ga/RProjects/datasets/clothing_reviews.csv"
echo "Downloading Reviews Dataset..."
if [ ! -f "$REVIEWS_PATH" ]; then
    wget -q -O "$REVIEWS_PATH" \
        "https://raw.githubusercontent.com/freestack/womens-ecommerce-clothing-reviews/master/Womens%20Clothing%20E-Commerce%20Reviews.csv" || \
    echo "Failed to download reviews dataset"
fi

# Verify dataset
if [ -f "$REVIEWS_PATH" ] && [ $(wc -l < "$REVIEWS_PATH") -gt 1000 ]; then
    echo "Reviews dataset ready: $(wc -l < "$REVIEWS_PATH") rows"
else
    echo "ERROR: Reviews dataset missing or empty"
    exit 1
fi

# 2. Prepare AFINN Lexicon
# Downloading AFINN-111 and converting to CSV (word, value)
LEXICON_PATH="/home/ga/RProjects/datasets/afinn_lexicon.csv"
echo "Preparing AFINN Lexicon..."
if [ ! -f "$LEXICON_PATH" ]; then
    # Download raw tab-separated file
    wget -q -O /tmp/AFINN-111.txt "https://raw.githubusercontent.com/fnielsen/afinn/master/afinn/data/AFINN-111.txt"
    
    # Convert to CSV: Add header, replace tab with comma
    echo "word,value" > "$LEXICON_PATH"
    cat /tmp/AFINN-111.txt | tr '\t' ',' >> "$LEXICON_PATH"
    rm /tmp/AFINN-111.txt
fi

# Verify lexicon
if [ -f "$LEXICON_PATH" ]; then
    echo "Lexicon ready: $(wc -l < "$LEXICON_PATH") words"
else
    echo "ERROR: Lexicon creation failed"
    exit 1
fi

# 3. Create Starter Script
SCRIPT_PATH="/home/ga/RProjects/sentiment_analysis.R"
cat > "$SCRIPT_PATH" << 'EOF'
# Sentiment Analysis of Women's Clothing Reviews
#
# Inputs:
# - Reviews: "datasets/clothing_reviews.csv"
# - Lexicon: "datasets/afinn_lexicon.csv"
#
# Outputs required in "output/":
# 1. class_sentiment_summary.csv
# 2. dresses_sentiment_dist.png
# 3. dresses_negative_words.csv

library(tidyverse)
# You may need to install tidytext: install.packages("tidytext")
library(tidytext)

# Load data
reviews <- read_csv("datasets/clothing_reviews.csv")
afinn <- read_csv("datasets/afinn_lexicon.csv")

# Your analysis here...

EOF
chown ga:ga "$SCRIPT_PATH"

# 4. Install dependencies (optional but helpful to speed up agent)
# We won't pre-install tidytext to test if agent can do it, 
# but we ensure base tidyverse is ready (handled by env setup).
# Note: task description says "You will need to install 'tidytext'"

# 5. Launch RStudio
echo "Launching RStudio..."
if ! is_rstudio_running; then
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio $SCRIPT_PATH &"
    sleep 10
else
    # Just open the file
    su - ga -c "DISPLAY=:1 rstudio $SCRIPT_PATH &"
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="