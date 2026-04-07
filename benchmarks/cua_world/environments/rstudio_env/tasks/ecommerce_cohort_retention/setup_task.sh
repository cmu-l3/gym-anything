#!/bin/bash
echo "=== Setting up ecommerce_cohort_retention task ==="

source /workspace/scripts/task_utils.sh

# Create output and datasets directories
mkdir -p /home/ga/RProjects/output
mkdir -p /home/ga/RProjects/datasets
mkdir -p /var/lib/rstudio/ground_truth

# Set permissions
chown -R ga:ga /home/ga/RProjects

# 1. Download the Dataset
DATA_URL="https://raw.githubusercontent.com/guipsamora/pandas_exercises/master/07_Visualization/Online_Retail/Online_Retail.csv"
DEST_FILE="/home/ga/RProjects/datasets/online_retail.csv"

if [ ! -f "$DEST_FILE" ]; then
    echo "Downloading Online Retail dataset..."
    wget -q -O "$DEST_FILE" "$DATA_URL" || {
        echo "Failed to download dataset. Using fallback mirror or creating dummy for testing if offline."
        # Fail hard in production, but for testing we might check other mirrors
        exit 1
    }
fi
chown ga:ga "$DEST_FILE"

# 2. Generate Ground Truth (Hidden from Agent)
# We run a correct R script to produce the expected CSV.
# This ensures we verify against the exact data environment.
echo "Generating ground truth data..."
cat > /tmp/generate_ground_truth.R << 'EOF'
suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(lubridate)
  library(tidyr)
})

# Load data
df <- read_csv("/home/ga/RProjects/datasets/online_retail.csv", col_types = cols())

# Cleaning
df_clean <- df %>%
  filter(!is.na(CustomerID)) %>%
  filter(Quantity > 0) %>%
  mutate(InvoiceDate = parse_date_time(InvoiceDate, orders = c("mdy HM", "ymd HMS", "d/m/Y H:M")))

# Cohort Analysis
df_cohort <- df_clean %>%
  mutate(InvoiceMonth = floor_date(InvoiceDate, "month")) %>%
  group_by(CustomerID) %>%
  mutate(AcquisitionMonth = min(InvoiceMonth)) %>%
  ungroup() %>%
  mutate(CohortIndex = interval(AcquisitionMonth, InvoiceMonth) %/% months(1))

cohort_data <- df_cohort %>%
  group_by(AcquisitionMonth, CohortIndex) %>%
  summarise(n_customers = n_distinct(CustomerID), .groups = 'drop')

cohort_sizes <- cohort_data %>%
  filter(CohortIndex == 0) %>%
  select(AcquisitionMonth, cohort_size = n_customers)

retention <- cohort_data %>%
  left_join(cohort_sizes, by = "AcquisitionMonth") %>%
  mutate(RetentionRate = n_customers / cohort_size) %>%
  select(AcquisitionMonth, CohortIndex, RetentionRate)

write_csv(retention, "/var/lib/rstudio/ground_truth/retention_ground_truth.csv")
EOF

# Run the generation script
Rscript /tmp/generate_ground_truth.R > /dev/null 2>&1
chmod 600 /var/lib/rstudio/ground_truth/retention_ground_truth.csv # Restrict access

# 3. Create a blank starter script for the agent
cat > /home/ga/RProjects/cohort_analysis.R << 'EOF'
# E-commerce Cohort Retention Analysis
#
# Dataset: /home/ga/RProjects/datasets/online_retail.csv
#
# Goal: Calculate monthly retention rates and visualize as a heatmap.
#
# Steps:
# 1. Load data and clean (remove missing CustomerID, negative Quantity)
# 2. Identify Acquisition Month for each customer
# 3. Calculate Cohort Index (months since acquisition)
# 4. Calculate Retention Rate (customers active / initial cohort size)
# 5. Save results to output/retention_rates.csv and output/retention_heatmap.png

library(tidyverse)
library(lubridate)

# Load data
df <- read_csv("/home/ga/RProjects/datasets/online_retail.csv")

# Your code here...
EOF
chown ga:ga /home/ga/RProjects/cohort_analysis.R

# 4. Record timestamp
date +%s > /tmp/task_start_time

# 5. Start RStudio
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/cohort_analysis.R &"
    sleep 10
else
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/cohort_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="