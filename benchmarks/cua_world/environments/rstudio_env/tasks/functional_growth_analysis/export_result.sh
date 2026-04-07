#!/bin/bash
echo "=== Exporting functional_growth_analysis result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_ts 2>/dev/null || echo "0")
take_screenshot /tmp/task_final.png

# Paths
CSV_PATH="/home/ga/RProjects/output/fpca_variance.csv"
MEAN_PNG="/home/ga/RProjects/output/mean_growth_curve.png"
PC1_PNG="/home/ga/RProjects/output/pc1_variation.png"
SCRIPT_PATH="/home/ga/RProjects/growth_analysis.R"

# Initialize variables
SCRIPT_EXISTS="false"
SCRIPT_IS_NEW="false"
HAS_FDA="false"
HAS_BSPLINE="false"
HAS_SMOOTH="false"
HAS_PCA="false"

CSV_EXISTS="false"
CSV_IS_NEW="false"
PC1_VARIANCE="0.0"

MEAN_EXISTS="false"
MEAN_IS_NEW="false"
MEAN_SIZE="0"

PC1_EXISTS="false"
PC1_IS_NEW="false"
PC1_SIZE="0"

# 1. Check Script
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    MTIME=$(stat -c %Y "$SCRIPT_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        SCRIPT_IS_NEW="true"
    fi
    
    CONTENT=$(cat "$SCRIPT_PATH")
    echo "$CONTENT" | grep -qi "fda" && HAS_FDA="true"
    echo "$CONTENT" | grep -qi "create.bspline.basis" && HAS_BSPLINE="true"
    echo "$CONTENT" | grep -qi "smooth.basis" && HAS_SMOOTH="true"
    echo "$CONTENT" | grep -qi "pca.fd" && HAS_PCA="true"
fi

# 2. Check CSV and extract variance
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    MTIME=$(stat -c %Y "$CSV_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        CSV_IS_NEW="true"
    fi

    # Extract PC1 variance (should be ~0.83-0.85 for this dataset)
    PC1_VARIANCE=$(python3 -c "
import csv, re
try:
    with open('$CSV_PATH', 'r') as f:
        text = f.read()
        # Find all floats
        floats = [float(x) for x in re.findall(r'0\.\d+|[1-9]\d*\.\d+', text)]
        # Look for the PC1 variance
        pc1_cands = [x for x in floats if 0.80 <= x <= 0.95]
        if pc1_cands:
            print(max(pc1_cands))
        else:
            # Check for percentages
            pc1_perc = [x for x in floats if 80.0 <= x <= 95.0]
            if pc1_perc:
                print(max(pc1_perc)/100.0)
            else:
                print('0.0')
except:
    print('0.0')
" 2>/dev/null || echo "0.0")
fi

# 3. Check PNGs
if [ -f "$MEAN_PNG" ]; then
    MEAN_EXISTS="true"
    MTIME=$(stat -c %Y "$MEAN_PNG")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        MEAN_IS_NEW="true"
    fi
    MEAN_SIZE=$(stat -c %s "$MEAN_PNG")
fi

if [ -f "$PC1_PNG" ]; then
    PC1_EXISTS="true"
    MTIME=$(stat -c %Y "$PC1_PNG")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        PC1_IS_NEW="true"
    fi
    PC1_SIZE=$(stat -c %s "$PC1_PNG")
fi

# Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "script_exists": $SCRIPT_EXISTS,
    "script_is_new": $SCRIPT_IS_NEW,
    "has_fda": $HAS_FDA,
    "has_bspline": $HAS_BSPLINE,
    "has_smooth": $HAS_SMOOTH,
    "has_pca": $HAS_PCA,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "pc1_variance": $PC1_VARIANCE,
    "mean_png_exists": $MEAN_EXISTS,
    "mean_png_is_new": $MEAN_IS_NEW,
    "mean_png_size": $MEAN_SIZE,
    "pc1_png_exists": $PC1_EXISTS,
    "pc1_png_is_new": $PC1_IS_NEW,
    "pc1_png_size": $PC1_SIZE
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="