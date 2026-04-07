#!/bin/bash
echo "=== Exporting Wine PCA Task Results ==="

source /workspace/scripts/task_utils.sh

# Paths
PCA_CSV="/home/ga/RProjects/output/wine_pca_summary.csv"
SIL_CSV="/home/ga/RProjects/output/wine_silhouette.csv"
RES_CSV="/home/ga/RProjects/output/wine_cluster_results.csv"
PLOT_PNG="/home/ga/RProjects/output/wine_analysis.png"
SCRIPT="/home/ga/RProjects/wine_analysis.R"

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
take_screenshot /tmp/wine_final.png

# Helper to get file stats
get_file_stats() {
    local f="$1"
    if [ -f "$f" ]; then
        local sz=$(stat -c %s "$f")
        local mt=$(stat -c %Y "$f")
        local new="false"
        if [ "$mt" -gt "$TASK_START" ]; then new="true"; fi
        echo "{\"exists\": true, \"size\": $sz, \"is_new\": $new, \"path\": \"$f\"}"
    else
        echo "{\"exists\": false}"
    fi
}

# Analyze content with Python
CONTENT_ANALYSIS=$(python3 << 'PYEOF'
import pandas as pd
import json
import os

results = {
    "pca_valid": False,
    "pca_eigen_sum": 0,
    "silhouette_valid": False,
    "best_k": 0,
    "cluster_rows": 0,
    "cluster_cols": [],
    "has_pc_cols": False,
    "plot_valid": False
}

# Check PCA Summary
try:
    if os.path.exists("/home/ga/RProjects/output/wine_pca_summary.csv"):
        df_pca = pd.read_csv("/home/ga/RProjects/output/wine_pca_summary.csv")
        results["pca_eigen_sum"] = float(df_pca['eigenvalue'].sum())
        # Should sum to ~11 (number of features) if scaled
        results["pca_valid"] = len(df_pca) == 11
except Exception as e:
    pass

# Check Silhouette
try:
    if os.path.exists("/home/ga/RProjects/output/wine_silhouette.csv"):
        df_sil = pd.read_csv("/home/ga/RProjects/output/wine_silhouette.csv")
        if 'avg_silhouette_width' in df_sil.columns and 'k' in df_sil.columns:
            best_row = df_sil.loc[df_sil['avg_silhouette_width'].idxmax()]
            results["best_k"] = int(best_row['k'])
            results["silhouette_valid"] = len(df_sil) >= 5
except Exception as e:
    pass

# Check Cluster Results
try:
    if os.path.exists("/home/ga/RProjects/output/wine_cluster_results.csv"):
        df_res = pd.read_csv("/home/ga/RProjects/output/wine_cluster_results.csv")
        results["cluster_rows"] = len(df_res)
        results["cluster_cols"] = list(df_res.columns)
        results["has_pc_cols"] = all(c in df_res.columns for c in ['PC1', 'PC2'])
except Exception as e:
    pass

print(json.dumps(results))
PYEOF
)

# Analyze R script content
SCRIPT_CONTENT_CHECK="false"
if [ -f "$SCRIPT" ]; then
    if grep -q "prcomp" "$SCRIPT" && grep -q "kmeans" "$SCRIPT"; then
        SCRIPT_CONTENT_CHECK="true"
    fi
fi

# Construct JSON
TEMP_JSON=$(mktemp /tmp/wine_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "files": {
        "pca_csv": $(get_file_stats "$PCA_CSV"),
        "sil_csv": $(get_file_stats "$SIL_CSV"),
        "res_csv": $(get_file_stats "$RES_CSV"),
        "plot_png": $(get_file_stats "$PLOT_PNG"),
        "script": $(get_file_stats "$SCRIPT")
    },
    "content": $CONTENT_ANALYSIS,
    "script_has_keywords": $SCRIPT_CONTENT_CHECK
}
EOF

# Safe copy
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="