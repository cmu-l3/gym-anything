#!/bin/bash
echo "=== Setting up manual_endogeneity_test_script task ==="

source /workspace/scripts/task_utils.sh

# Ensure mroz.gdt is available (it's a standard dataset, often in poe5 or gretl data)
# We need to make sure it's in the documents folder for easy access
DATASET="mroz.gdt"
DATA_DEST="/home/ga/Documents/gretl_data/$DATASET"

# Check standard locations if not already in user dir
if [ ! -f "$DATA_DEST" ]; then
    FOUND=false
    for loc in "/opt/gretl_data/poe5" "/usr/share/gretl/data/misc" "/usr/share/gretl/data/wooldridge"; do
        if [ -f "$loc/$DATASET" ]; then
            cp "$loc/$DATASET" "$DATA_DEST"
            chown ga:ga "$DATA_DEST"
            chmod 644 "$DATA_DEST"
            FOUND=true
            echo "Copied $DATASET from $loc"
            break
        fi
    done
    
    # If still not found, try to download (fallback)
    if [ "$FOUND" = "false" ]; then
        echo "Downloading mroz.gdt..."
        wget -q -O "$DATA_DEST" "https://www.learneconometrics.com/gretl/poe5/data/mroz.gdt" 2>/dev/null || true
        chown ga:ga "$DATA_DEST" 2>/dev/null || true
    fi
fi

# Clear output directory
rm -f /home/ga/Documents/gretl_output/endogeneity_test_results.txt 2>/dev/null || true

# Standard task setup: kill gretl, launch with dataset
setup_gretl_task "$DATASET" "endogeneity_test"

# Record start time explicitly for this task
date +%s > /tmp/task_start_time

echo ""
echo "============================================================"
echo "TASK: Manual Endogeneity Test (Control Function Approach)"
echo "============================================================"
echo ""
echo "Dataset 'mroz.gdt' is loaded."
echo "Goal: Test endogeneity of 'educ' in wage equation."
echo ""
echo "Steps:"
echo "1. Restrict sample: lfp = 1"
echo "2. Stage 1: Regress 'educ' on const, exper, expersq, motheduc"
echo "3. Save residuals as 'v_hat'"
echo "4. Stage 2: Regress 'lwg' on const, educ, exper, expersq, v_hat"
echo "5. Save Stage 2 results to /home/ga/Documents/gretl_output/endogeneity_test_results.txt"
echo "============================================================"