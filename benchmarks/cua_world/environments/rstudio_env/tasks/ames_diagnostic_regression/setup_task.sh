#!/bin/bash
echo "=== Setting up Ames Diagnostic Regression Task ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

if ! type is_rstudio_running &>/dev/null; then
    is_rstudio_running() { pgrep -f "rstudio" > /dev/null 2>&1; }
    focus_rstudio() { local w=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i rstudio | head -1 | awk '{print $1}'); [ -n "$w" ] && DISPLAY=:1 wmctrl -i -a "$w"; }
    maximize_rstudio() { local w=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i rstudio | head -1 | awk '{print $1}'); [ -n "$w" ] && DISPLAY=:1 wmctrl -i -r "$w" -b add,maximized_vert,maximized_horz; }
fi

# ── 1. Create directories ──────────────────────────────────────────────────────
mkdir -p /home/ga/RProjects/datasets
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects

# ── 2. Install R packages ──────────────────────────────────────────────────────
echo "Installing R packages..."
R --vanilla --slave -e "
options(repos = c(CRAN = 'https://cloud.r-project.org'))
pkgs <- c('AmesHousing', 'car', 'lmtest', 'Metrics', 'ggplot2', 'dplyr', 'MASS')
for (pkg in pkgs) {
    if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
        cat('Installing', pkg, '\n')
        install.packages(pkg, quiet = TRUE)
    } else {
        cat(pkg, 'already installed\n')
    }
}
cat('Package installation complete\n')
" 2>&1 | tail -10

# ── 3. Generate train/test split from AmesHousing package ──────────────────────
echo "Generating Ames Housing train/test split..."
R --vanilla --slave << 'REOF'
library(AmesHousing)
data(ames_raw)
ames <- ames_raw

# Clean column names: remove spaces, dots, slashes -> CamelCase
names(ames) <- gsub("[^A-Za-z0-9]", "", names(ames))

# Identify and standardize the SalePrice column
sp_candidates <- grep("^[Ss]ale[Pp]rice$", names(ames), value = TRUE)
if (length(sp_candidates) == 1) {
    names(ames)[names(ames) == sp_candidates[1]] <- "SalePrice"
}

# Remove identifier columns (Order, PID) — not predictive features
ames$Order <- NULL
ames$PID   <- NULL

# Drop rows with missing SalePrice (should be 0, but be safe)
ames <- ames[!is.na(ames$SalePrice), ]

# Add sequential Id
ames$Id <- seq_len(nrow(ames))

# Deterministic 70/30 split
set.seed(2024)
n <- nrow(ames)
train_idx <- sample(seq_len(n), size = round(0.7 * n))

train <- ames[train_idx, ]
test  <- ames[-train_idx, ]

# Save ground truth (hidden from agent)
ground_truth <- data.frame(Id = test$Id, SalePrice = test$SalePrice)
write.csv(ground_truth, "/tmp/.ames_ground_truth.csv", row.names = FALSE)

# Remove target from test set
test$SalePrice <- NULL

# Save datasets
write.csv(train, "/home/ga/RProjects/datasets/ames_train.csv", row.names = FALSE)
write.csv(test,  "/home/ga/RProjects/datasets/ames_test.csv",  row.names = FALSE)

cat("Train:", nrow(train), "rows x", ncol(train), "cols\n")
cat("Test: ", nrow(test),  "rows x", ncol(test),  "cols\n")
cat("SalePrice range: $", min(train$SalePrice), "- $", max(train$SalePrice), "\n")
REOF

# Verify data was generated
if [ ! -f "/home/ga/RProjects/datasets/ames_train.csv" ] || \
   [ ! -f "/home/ga/RProjects/datasets/ames_test.csv" ] || \
   [ ! -f "/tmp/.ames_ground_truth.csv" ]; then
    echo "CRITICAL: Ames Housing data generation failed"
    exit 1
fi

echo "Data generated successfully:"
wc -l /home/ga/RProjects/datasets/ames_train.csv
wc -l /home/ga/RProjects/datasets/ames_test.csv

chown -R ga:ga /home/ga/RProjects/

# ── 4. Remove stale outputs BEFORE recording timestamp ─────────────────────────
rm -f /home/ga/RProjects/output/ames_predictions.csv 2>/dev/null || true
rm -f /home/ga/RProjects/output/ames_diagnostics.csv 2>/dev/null || true
rm -f /home/ga/RProjects/output/ames_coefficients.csv 2>/dev/null || true
rm -f /home/ga/RProjects/output/ames_diagnostic_plots.png 2>/dev/null || true
rm -f /home/ga/RProjects/ames_analysis.R 2>/dev/null || true

# ── 5. Create minimal starter script BEFORE recording timestamp ────────────────
cat > /home/ga/RProjects/ames_analysis.R << 'RSCRIPT'
# Ames Housing: Diagnostic-Gated Regression
#
# Data:
#   Train: /home/ga/RProjects/datasets/ames_train.csv  (2051 obs, 80 features + SalePrice)
#   Test:  /home/ga/RProjects/datasets/ames_test.csv   (879 obs, 80 features, no SalePrice)
#
# Quality gates (all must pass simultaneously):
#   1. RMSLE < 0.16 on test set
#   2. VIF < 5 for every predictor
#   3. Adjusted R-squared > 0.82 on training data
#   4. Max Cook's distance < 1.0
#
# Deliverables (save to /home/ga/RProjects/output/):
#   ames_predictions.csv      - Id, predicted_price (879 rows, dollar scale)
#   ames_diagnostics.csv      - test_name, statistic, threshold, pass
#   ames_coefficients.csv     - term, estimate, std_error, p_value
#   ames_diagnostic_plots.png - 2x2: resid vs fitted, Q-Q, Scale-Location, Cook's D
#
# Pre-installed packages: car, lmtest, Metrics, ggplot2, dplyr, MASS

RSCRIPT
chown ga:ga /home/ga/RProjects/ames_analysis.R

# ── 6. Record task start timestamp ─────────────────────────────────────────────
date +%s > /tmp/ames_diagnostic_regression_start_ts

# ── 7. Launch RStudio ──────────────────────────────────────────────────────────
echo "Ensuring RStudio is running..."
if ! is_rstudio_running 2>/dev/null; then
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/ames_analysis.R >> /home/ga/rstudio.log 2>&1 &"
    sleep 15
else
    focus_rstudio 2>/dev/null || true
fi

# Open the starter script in RStudio
su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/ames_analysis.R >> /home/ga/rstudio.log 2>&1 &" 2>/dev/null || true
sleep 5

focus_rstudio 2>/dev/null || true
maximize_rstudio 2>/dev/null || true
sleep 2

take_screenshot /tmp/ames_diagnostic_regression_start_screenshot.png

echo "=== Ames Diagnostic Regression Setup Complete ==="
echo "Train: /home/ga/RProjects/datasets/ames_train.csv"
echo "Test:  /home/ga/RProjects/datasets/ames_test.csv"
echo "Script: /home/ga/RProjects/ames_analysis.R"
echo "Output: /home/ga/RProjects/output/"
