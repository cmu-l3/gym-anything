#!/bin/bash
echo "=== Exporting ecommerce_cohort_retention result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
take_screenshot /tmp/task_final.png

OUTPUT_CSV="/home/ga/RProjects/output/retention_rates.csv"
OUTPUT_PLOT="/home/ga/RProjects/output/retention_heatmap.png"
GROUND_TRUTH="/var/lib/rstudio/ground_truth/retention_ground_truth.csv"
SCRIPT_PATH="/home/ga/RProjects/cohort_analysis.R"

# 1. Check Output CSV
CSV_EXISTS="false"
CSV_IS_NEW="false"
CSV_ROWS=0

if [ -f "$OUTPUT_CSV" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$OUTPUT_CSV" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_IS_NEW="true"
    fi
    CSV_ROWS=$(wc -l < "$OUTPUT_CSV")
fi

# 2. Check Output Plot
PLOT_EXISTS="false"
PLOT_IS_NEW="false"
PLOT_SIZE_BYTES=0

if [ -f "$OUTPUT_PLOT" ]; then
    PLOT_EXISTS="true"
    PLOT_MTIME=$(stat -c %Y "$OUTPUT_PLOT" 2>/dev/null || echo "0")
    PLOT_SIZE_BYTES=$(stat -c %s "$OUTPUT_PLOT")
    if [ "$PLOT_MTIME" -gt "$TASK_START" ]; then
        PLOT_IS_NEW="true"
    fi
fi

# 3. Check Script Modification
SCRIPT_MODIFIED="false"
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
fi

# 4. Compare Data Accuracy (Python)
# We use a python script to load both CSVs and compare key values
ACCURACY_METRICS=$(python3 << 'EOF'
import pandas as pd
import numpy as np
import sys
import json

try:
    agent_csv = "/home/ga/RProjects/output/retention_rates.csv"
    gt_csv = "/var/lib/rstudio/ground_truth/retention_ground_truth.csv"

    # Load agent data
    try:
        df_agent = pd.read_csv(agent_csv)
    except:
        print(json.dumps({"error": "Read failed", "score": 0}))
        sys.exit(0)

    # Load ground truth
    df_gt = pd.read_csv(gt_csv)

    # Normalize columns (lowercase)
    df_agent.columns = [c.lower() for c in df_agent.columns]
    df_gt.columns = [c.lower() for c in df_gt.columns]

    # Find required columns
    # We look for 'retention' or 'rate' column
    ret_col = next((c for c in df_agent.columns if 'retention' in c or 'rate' in c), None)
    idx_col = next((c for c in df_agent.columns if 'index' in c or 'cohortindex' in c), None)
    
    if not ret_col or not idx_col:
        print(json.dumps({"error": "Missing columns", "score": 0, "columns": list(df_agent.columns)}))
        sys.exit(0)

    # Merge on index and roughly date (requires parsing) if possible
    # For simplicity, we filter for a specific known cohort to spot check
    # Let's check the '2010-12-01' cohort (first one)
    
    # Simple check: Mean retention rate at Index 1 across all cohorts
    # GT Mean
    gt_idx1 = df_gt[df_gt['cohortindex'] == 1]
    gt_mean = gt_idx1['retentionrate'].mean() if not gt_idx1.empty else 0
    
    # Agent Mean
    agent_idx1 = df_agent[df_agent[idx_col] == 1]
    agent_mean = agent_idx1[ret_col].mean() if not agent_idx1.empty else 0
    
    # Calculate error
    diff = abs(gt_mean - agent_mean)
    accuracy_score = max(0, 100 - (diff * 1000)) # Penalize deviation

    # Specific point check: 2010-12 Index 1 (should be ~0.38)
    # This is harder to match without strict date parsing, so we stick to aggregate stats
    
    result = {
        "gt_mean_idx1": float(gt_mean),
        "agent_mean_idx1": float(agent_mean),
        "diff": float(diff),
        "accuracy_score": float(accuracy_score),
        "columns_found": list(df_agent.columns)
    }
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"error": str(e), "score": 0}))
EOF
)

# 5. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_rows": $CSV_ROWS,
    "plot_exists": $PLOT_EXISTS,
    "plot_is_new": $PLOT_IS_NEW,
    "plot_size_bytes": $PLOT_SIZE_BYTES,
    "script_modified": $SCRIPT_MODIFIED,
    "accuracy_metrics": $ACCURACY_METRICS,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON generated."
cat /tmp/task_result.json