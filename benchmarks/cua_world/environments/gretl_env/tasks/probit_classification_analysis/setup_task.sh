#!/bin/bash
echo "=== Setting up Probit Classification Task ==="

source /workspace/scripts/task_utils.sh

# Define dataset location
DATASET="mroz.gdt"
DATA_DIR="/home/ga/Documents/gretl_data"
MASTER_DIR="/opt/gretl_data/poe5"

# Ensure dataset exists, if not in user dir, copy from master or create dummy/download
if [ ! -f "$DATA_DIR/$DATASET" ]; then
    echo "Copying $DATASET..."
    if [ -f "$MASTER_DIR/$DATASET" ]; then
        cp "$MASTER_DIR/$DATASET" "$DATA_DIR/$DATASET"
    else
        # Fallback if mroz is missing (unlikely given env setup, but safe to handle)
        # Check system paths
        FOUND=$(find /usr/share/gretl -name "mroz.gdt" | head -n 1)
        if [ -n "$FOUND" ]; then
            cp "$FOUND" "$DATA_DIR/$DATASET"
        else
            echo "WARNING: mroz.gdt not found. Downloading..."
            wget -q -O "$DATA_DIR/$DATASET" "https://www.learneconometrics.com/gretl/poe5/data/mroz.gdt" || \
            echo "Failed to download mroz.gdt"
        fi
    fi
fi

# Set permissions
chown ga:ga "$DATA_DIR/$DATASET"
chmod 644 "$DATA_DIR/$DATASET"

# Setup Gretl with this dataset
# This kills old instances, cleans output dir, launches Gretl, maximizes window
setup_gretl_task "$DATASET" "probit_task"

echo "=== Task Setup Complete ==="
echo "Dataset $DATASET loaded."
echo "Goal: Estimate Probit (lfp ~ k5 k618 age wc hc inc) and extract classification accuracy."