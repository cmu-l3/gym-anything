#!/bin/bash
echo "=== Setting up genomics_variant_qc task ==="

source /workspace/scripts/task_utils.sh

# Create required directories
mkdir -p /home/ga/RProjects/output
mkdir -p /home/ga/RProjects/datasets
chown -R ga:ga /home/ga/RProjects

# Remove stale output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/RProjects/output/variant_qc_summary.csv 2>/dev/null
rm -f /home/ga/RProjects/output/population_pca.png 2>/dev/null
rm -f /home/ga/RProjects/variant_analysis.R 2>/dev/null

# Download real VCF data (Phytophthora infestans dataset from vcfR repository)
echo "Downloading raw VCF dataset..."
VCF_PATH="/home/ga/RProjects/datasets/phytophthora_raw.vcf.gz"
wget -q -O "$VCF_PATH" "https://raw.githubusercontent.com/grunwaldlab/vcfR/master/inst/extdata/pinf_sc50.vcf.gz"

if [ ! -f "$VCF_PATH" ] || [ ! -s "$VCF_PATH" ]; then
    echo "ERROR: Failed to download VCF dataset."
    exit 1
fi
chown ga:ga "$VCF_PATH"
echo "Dataset downloaded successfully: $(du -h $VCF_PATH | cut -f1)"

# Install required packages if not already present
echo "Checking and installing required R packages (vcfR, adegenet)..."
R --vanilla --slave << 'REOF'
options(repos = c(CRAN = "https://cloud.r-project.org"))
pkgs <- c("vcfR", "adegenet", "ggplot2", "dplyr")
for (pkg in pkgs) {
    if (!requireNamespace(pkg, quietly=TRUE)) {
        message(paste("Installing", pkg, "..."))
        install.packages(pkg, quiet=TRUE)
    }
}
REOF

# Create starter R script BEFORE recording timestamp
cat > /home/ga/RProjects/variant_analysis.R << 'RSCRIPT'
# Genomics Variant Quality Control and PCA
# Dataset: Phytophthora infestans GBS data
# File: /home/ga/RProjects/datasets/phytophthora_raw.vcf.gz

library(vcfR)
library(adegenet)

# TODO:
# 1. Read the VCF file
# 2. Filter variants (> 20% missing OR mean DP < 5 should be REMOVED)
# 3. Save variant_qc_summary.csv (columns: original_variants, filtered_variants)
# 4. Convert to genlight and perform PCA
# 5. Save population_pca.png

RSCRIPT
chown ga:ga /home/ga/RProjects/variant_analysis.R

# Record task start timestamp AFTER starter creation (anti-gaming: starter mtime <= task_start)
date +%s > /tmp/task_start_ts

# Ensure RStudio is running
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/variant_analysis.R &"
    sleep 10
else
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/variant_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
echo "Dataset: $VCF_PATH"