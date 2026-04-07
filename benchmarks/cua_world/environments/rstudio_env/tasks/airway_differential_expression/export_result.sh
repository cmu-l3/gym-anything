#!/bin/bash
echo "=== Exporting Airway Task Results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/RProjects/output"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Verify DE Results CSV
RES_CSV="$OUTPUT_DIR/de_results.csv"
RES_EXISTS=false
RES_NEW=false
RES_COLS=false
RES_SIG_COUNT=0
RES_VALID=false

if [ -f "$RES_CSV" ]; then
    RES_EXISTS=true
    MTIME=$(stat -c %Y "$RES_CSV")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        RES_NEW=true
    fi
    
    # Analyze CSV content with Python
    PY_ANALYSIS=$(python3 << 'PYEOF'
import pandas as pd
import sys
try:
    df = pd.read_csv("'$RES_CSV'")
    required = {'gene_id', 'log2FoldChange', 'padj'}
    # Allow loose column matching
    cols = set(df.columns)
    has_cols = len(required.intersection(cols)) >= 2 # At least logFC and padj
    
    # Check for significant genes (padj < 0.05 & |logFC| > 1)
    # Handle NAs
    sig_df = df.dropna(subset=['padj', 'log2FoldChange'])
    sig_count = len(sig_df[(sig_df['padj'] < 0.05) & (sig_df['log2FoldChange'].abs() > 1)])
    
    print(f"{str(has_cols).lower()},{sig_count}")
except Exception as e:
    print(f"false,0")
PYEOF
)
    RES_COLS=$(echo $PY_ANALYSIS | cut -d',' -f1)
    RES_SIG_COUNT=$(echo $PY_ANALYSIS | cut -d',' -f2)
fi

# 2. Verify Plots
VOLCANO="$OUTPUT_DIR/volcano_plot.png"
HEATMAP="$OUTPUT_DIR/top_genes_heatmap.png"
VOLCANO_EXISTS=false
HEATMAP_EXISTS=false
VOLCANO_SIZE=0
HEATMAP_SIZE=0

if [ -f "$VOLCANO" ] && [ "$(stat -c %Y "$VOLCANO")" -gt "$TASK_START" ]; then
    VOLCANO_EXISTS=true
    VOLCANO_SIZE=$(stat -c %s "$VOLCANO")
fi

if [ -f "$HEATMAP" ] && [ "$(stat -c %Y "$HEATMAP")" -gt "$TASK_START" ]; then
    HEATMAP_EXISTS=true
    HEATMAP_SIZE=$(stat -c %s "$HEATMAP")
fi

# 3. Verify Summary CSV
SUM_CSV="$OUTPUT_DIR/de_summary.csv"
SUM_EXISTS=false
SUM_VALID=false

if [ -f "$SUM_CSV" ] && [ "$(stat -c %Y "$SUM_CSV")" -gt "$TASK_START" ]; then
    SUM_EXISTS=true
    # Check if it has data
    if [ $(wc -l < "$SUM_CSV") -ge 2 ]; then
        SUM_VALID=true
    fi
fi

# 4. Verify R Script
SCRIPT="/home/ga/RProjects/airway_de_analysis.R"
SCRIPT_MODIFIED=false
SCRIPT_CONTENT_CHECK=false

if [ -f "$SCRIPT" ]; then
    MTIME=$(stat -c %Y "$SCRIPT")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED=true
    fi
    
    CONTENT=$(cat "$SCRIPT")
    if echo "$CONTENT" | grep -qE "DESeq|edgeR|limma|read\.csv|results|ggplot|pheatmap"; then
        SCRIPT_CONTENT_CHECK=true
    fi
fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "res_csv": {
        "exists": $RES_EXISTS,
        "is_new": $RES_NEW,
        "has_columns": $RES_COLS,
        "sig_gene_count": $RES_SIG_COUNT
    },
    "plots": {
        "volcano_exists": $VOLCANO_EXISTS,
        "volcano_size": $VOLCANO_SIZE,
        "heatmap_exists": $HEATMAP_EXISTS,
        "heatmap_size": $HEATMAP_SIZE
    },
    "summary": {
        "exists": $SUM_EXISTS,
        "valid": $SUM_VALID
    },
    "script": {
        "modified": $SCRIPT_MODIFIED,
        "content_check": $SCRIPT_CONTENT_CHECK
    }
}
EOF

# Move to final location
chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json