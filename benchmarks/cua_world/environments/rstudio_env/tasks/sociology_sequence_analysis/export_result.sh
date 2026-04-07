#!/bin/bash
echo "=== Exporting Sequence Analysis Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
take_screenshot /tmp/task_end.png

# --- Check Clusters CSV ---
CLUSTERS_CSV="/home/ga/RProjects/output/career_clusters.csv"
CLUSTERS_EXISTS=false
CLUSTERS_IS_NEW=false
CLUSTERS_ROWS=0
CLUSTERS_COLS_VALID=false
VALID_CLUSTER_COUNT=false

if [ -f "$CLUSTERS_CSV" ]; then
    CLUSTERS_EXISTS=true
    MTIME=$(stat -c %Y "$CLUSTERS_CSV" 2>/dev/null || echo "0")
    [ "$MTIME" -gt "$TASK_START" ] && CLUSTERS_IS_NEW=true
    
    # Count rows (excluding header)
    CLUSTERS_ROWS=$(awk 'NR>1' "$CLUSTERS_CSV" | wc -l)
    
    # Check headers
    HEADER=$(head -1 "$CLUSTERS_CSV" | tr '[:upper:]' '[:lower:]')
    if echo "$HEADER" | grep -q "cluster" && echo "$HEADER" | grep -q "id"; then
        CLUSTERS_COLS_VALID=true
    fi

    # Check number of unique clusters (should be 4)
    UNIQUE_CLUSTERS=$(awk -F, 'NR>1 {print $2}' "$CLUSTERS_CSV" | tr -d '"' | sort -u | wc -l)
    if [ "$UNIQUE_CLUSTERS" -eq 4 ]; then
        VALID_CLUSTER_COUNT=true
    fi
fi

# --- Check Plot PNG ---
PLOT_PNG="/home/ga/RProjects/output/cluster_trajectories.png"
PLOT_EXISTS=false
PLOT_IS_NEW=false
PLOT_SIZE_KB=0

if [ -f "$PLOT_PNG" ]; then
    PLOT_EXISTS=true
    MTIME=$(stat -c %Y "$PLOT_PNG" 2>/dev/null || echo "0")
    [ "$MTIME" -gt "$TASK_START" ] && PLOT_IS_NEW=true
    PLOT_SIZE_KB=$(du -k "$PLOT_PNG" | cut -f1)
fi

# --- Check Durations CSV ---
DUR_CSV="/home/ga/RProjects/output/state_durations.csv"
DUR_EXISTS=false
DUR_IS_NEW=false

if [ -f "$DUR_CSV" ]; then
    DUR_EXISTS=true
    MTIME=$(stat -c %Y "$DUR_CSV" 2>/dev/null || echo "0")
    [ "$MTIME" -gt "$TASK_START" ] && DUR_IS_NEW=true
fi

# --- Check R Script ---
SCRIPT="/home/ga/RProjects/sequence_analysis.R"
SCRIPT_MODIFIED=false
HAS_TRAMINER=false
HAS_SEQDEF=false
HAS_SEQDIST=false
HAS_HCLUST=false
HAS_OM=false

if [ -f "$SCRIPT" ]; then
    MTIME=$(stat -c %Y "$SCRIPT" 2>/dev/null || echo "0")
    [ "$MTIME" -gt "$TASK_START" ] && SCRIPT_MODIFIED=true
    
    CONTENT=$(cat "$SCRIPT")
    echo "$CONTENT" | grep -qi "TraMineR" && HAS_TRAMINER=true
    echo "$CONTENT" | grep -qi "seqdef" && HAS_SEQDEF=true
    echo "$CONTENT" | grep -qi "seqdist" && HAS_SEQDIST=true
    echo "$CONTENT" | grep -qi "hclust" && HAS_HCLUST=true
    echo "$CONTENT" | grep -qi "method.*=.*OM" && HAS_OM=true
    # Also check for "OM" string generally as agent might define costs separately
    echo "$CONTENT" | grep -q "OM" && HAS_OM=true
fi

# Build JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "clusters_exists": $CLUSTERS_EXISTS,
    "clusters_is_new": $CLUSTERS_IS_NEW,
    "clusters_rows": $CLUSTERS_ROWS,
    "clusters_cols_valid": $CLUSTERS_COLS_VALID,
    "valid_cluster_count": $VALID_CLUSTER_COUNT,
    "plot_exists": $PLOT_EXISTS,
    "plot_is_new": $PLOT_IS_NEW,
    "plot_size_kb": $PLOT_SIZE_KB,
    "durations_exists": $DUR_EXISTS,
    "durations_is_new": $DUR_IS_NEW,
    "script_modified": $SCRIPT_MODIFIED,
    "has_traminer": $HAS_TRAMINER,
    "has_seqdef": $HAS_SEQDEF,
    "has_seqdist": $HAS_SEQDIST,
    "has_hclust": $HAS_HCLUST,
    "has_om": $HAS_OM,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/sequence_analysis_result.json 2>/dev/null || sudo rm -f /tmp/sequence_analysis_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/sequence_analysis_result.json
chmod 666 /tmp/sequence_analysis_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/sequence_analysis_result.json"