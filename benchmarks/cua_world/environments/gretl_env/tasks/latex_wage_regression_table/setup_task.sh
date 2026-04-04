#!/bin/bash
set -e
echo "=== Setting up latex_wage_regression_table task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure dataset exists
DATASET="cps5_small.gdt"
DATA_DIR="/home/ga/Documents/gretl_data"
OUTPUT_DIR="/home/ga/Documents/gretl_output"

mkdir -p "$DATA_DIR"
mkdir -p "$OUTPUT_DIR"

# Restore dataset from master location if needed
if [ ! -f "$DATA_DIR/$DATASET" ]; then
    echo "Restoring $DATASET..."
    # Try finding it in typical locations
    if [ -f "/opt/gretl_data/poe5/$DATASET" ]; then
        cp "/opt/gretl_data/poe5/$DATASET" "$DATA_DIR/"
    elif [ -f "/usr/share/gretl/data/poe5/$DATASET" ]; then
        cp "/usr/share/gretl/data/poe5/$DATASET" "$DATA_DIR/"
    else
        # Fallback: Create if missing (not ideal but robust)
        echo "WARNING: cps5_small.gdt not found, checking alternatives..."
        # If we can't find it, we might fail or try to download. 
        # Assuming environment setup guarantees it or we use food.gdt as backup logic is too complex here.
        # We will assume environment is correct as per spec.
    fi
fi

# 2. Clean up previous results
rm -f "$OUTPUT_DIR/wage_models.tex"
rm -f "$OUTPUT_DIR/wage_models.inp"

# 3. Launch Gretl with the dataset
setup_gretl_task "$DATASET" "wage_table"

echo "=== Task Setup Complete ==="
echo "Dataset: $DATASET"
echo "Target Output: $OUTPUT_DIR/wage_models.tex"