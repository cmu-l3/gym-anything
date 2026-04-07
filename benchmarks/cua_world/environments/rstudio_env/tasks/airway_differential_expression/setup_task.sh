#!/bin/bash
echo "=== Setting up Airway RNA-Seq Task ==="

source /workspace/scripts/task_utils.sh

# Create directories
mkdir -p /home/ga/RProjects/datasets
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects

# Install required Bioconductor packages if not present
# We check for 'airway' data package and 'DESeq2'
echo "Checking R packages..."
R --vanilla --slave << 'REOF'
required_pkgs <- c("BiocManager", "ggplot2", "pheatmap")
for (p in required_pkgs) {
    if (!requireNamespace(p, quietly=TRUE)) install.packages(p, repos="https://cloud.r-project.org/", quiet=TRUE)
}

if (!requireNamespace("airway", quietly=TRUE)) {
    BiocManager::install("airway", update=FALSE, ask=FALSE, quiet=TRUE)
}
if (!requireNamespace("DESeq2", quietly=TRUE)) {
    BiocManager::install("DESeq2", update=FALSE, ask=FALSE, quiet=TRUE)
}
REOF

# Extract data to CSVs (Agent must load these, simulating real workflow)
echo "Extracting airway dataset to CSVs..."
R --vanilla --slave << 'REOF'
suppressPackageStartupMessages(library(airway))
data(airway)

# Extract counts
counts <- assay(airway)
# Add gene IDs as a column for easier loading
counts_df <- as.data.frame(counts)
counts_df$gene_id <- rownames(counts_df)
counts_df <- counts_df[, c("gene_id", colnames(counts))] # Move ID to front
write.csv(counts_df, "/home/ga/RProjects/datasets/airway_counts.csv", row.names=FALSE)

# Extract coldata
coldata <- as.data.frame(colData(airway))
# Ensure sample IDs are a column
coldata$sample_id <- rownames(coldata)
write.csv(coldata, "/home/ga/RProjects/datasets/airway_coldata.csv", row.names=FALSE)
REOF

# Verify data extraction
if [ ! -f /home/ga/RProjects/datasets/airway_counts.csv ]; then
    echo "ERROR: Failed to create count matrix."
    exit 1
fi
chown -R ga:ga /home/ga/RProjects/datasets

# Create a starter script
cat > /home/ga/RProjects/airway_de_analysis.R << 'EOF'
# RNA-Seq Differential Expression Analysis
# Dataset: Airway Smooth Muscle Cells (Treated vs Untreated)
#
# TODO:
# 1. Load data from datasets/airway_counts.csv and datasets/airway_coldata.csv
# 2. Run differential expression analysis (e.g., using DESeq2)
# 3. Save results to output/de_results.csv
# 4. Generate Volcano Plot (output/volcano_plot.png) and Heatmap (output/top_genes_heatmap.png)
# 5. Save summary stats to output/de_summary.csv

library(ggplot2)
# library(DESeq2) # Uncomment when ready

EOF
chown ga:ga /home/ga/RProjects/airway_de_analysis.R

# Record task start time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# Record initial state
echo "Recording initial state..."
rm -f /home/ga/RProjects/output/* 2>/dev/null || true

# Start RStudio
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/airway_de_analysis.R &"
    sleep 10
else
    # Open the file if RStudio is running
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/airway_de_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="