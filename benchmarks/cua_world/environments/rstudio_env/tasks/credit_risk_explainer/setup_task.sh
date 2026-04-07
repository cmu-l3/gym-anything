#!/bin/bash
echo "=== Setting up Credit Risk Explainer Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Create directories
mkdir -p /home/ga/RProjects/datasets
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects

# Prepare the German Credit Dataset
# We download the raw UCI data and apply a quick R script to clean it
# so the agent doesn't have to deal with cryptic "A11", "A12" codes.
DATA_FILE="/home/ga/RProjects/datasets/german_credit.csv"

if [ ! -f "$DATA_FILE" ]; then
    echo "Preparing German Credit dataset..."
    
    # Download raw data
    wget -q -O /tmp/german.data "https://archive.ics.uci.edu/ml/machine-learning-databases/statlog/german/german.data"
    
    # Create cleaning script
    cat > /tmp/clean_data.R << 'EOF'
data <- read.table("/tmp/german.data", header=FALSE)
colnames(data) <- c("checking_balance", "months_loan_duration", "credit_history", 
                    "purpose", "amount", "savings_balance", "employment_length", 
                    "installment_rate", "personal_status", "other_debtors", 
                    "residence_history", "property", "age", "other_installment_plans", 
                    "housing", "existing_credits", "job", "dependents", 
                    "telephone", "foreign_worker", "default")

# Map integer default (1=Good, 2=Bad) to factor ("no", "yes")
data$default <- factor(ifelse(data$default == 1, "no", "yes"), levels=c("no", "yes"))

# Map cryptic codes to readable strings for a few key columns to make the task realistic
# (Checking balance is a strong predictor)
levels(data$checking_balance) <- c("< 0 DM", "0 - 200 DM", "> 200 DM", "unknown")

write.csv(data, "/home/ga/RProjects/datasets/german_credit.csv", row.names=FALSE)
EOF
    
    # Run cleaning script
    Rscript /tmp/clean_data.R
    rm -f /tmp/german.data /tmp/clean_data.R
fi

chown ga:ga "$DATA_FILE"

# Pre-install key ML packages if not present (ranger is standard but ensure it)
echo "Ensuring required packages..."
R --vanilla --slave << 'REOF'
pkgs <- c("ranger", "randomForest", "pdp", "vip", "pROC", "caret")
for (pkg in pkgs) {
    if (!requireNamespace(pkg, quietly=TRUE)) {
        install.packages(pkg, repos="https://cloud.r-project.org/", quiet=TRUE)
    }
}
REOF

# Create empty analysis script for agent
cat > /home/ga/RProjects/credit_risk_analysis.R << 'EOF'
# Credit Risk Modeling and Explainability
# Goal: Train Random Forest, Evaluate, and Explain (Importance + PDP)

library(tidyverse)
# Add your library loading here (e.g., ranger, pdp, pROC)

# 1. Load Data
data <- read.csv("datasets/german_credit.csv")
data$default <- as.factor(data$default)

# Your code here...
EOF
chown ga:ga /home/ga/RProjects/credit_risk_analysis.R

# Remove stale outputs
rm -f /home/ga/RProjects/output/*

# Record start time
date +%s > /tmp/task_start_time

# Start RStudio
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/credit_risk_analysis.R &"
    sleep 8
else
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/credit_risk_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="