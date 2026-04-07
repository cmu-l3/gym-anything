#!/bin/bash
echo "=== Exporting task result ==="

# Source utilities
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
else
    take_screenshot() { DISPLAY=:1 scrot "$1" 2>/dev/null || true; }
fi

# Take final screenshot of the environment
take_screenshot /tmp/task_final.png

# Get start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define expected files
DIST_CSV="/home/ga/RProjects/output/woodmouse_dist.csv"
NWK_FILE="/home/ga/RProjects/output/woodmouse_tree.nwk"
PNG_FILE="/home/ga/RProjects/output/woodmouse_tree_plot.png"
SCRIPT_FILE="/home/ga/RProjects/woodmouse_phylogeny.R"

# 1. Check Distance CSV
DIST_EXISTS=false
DIST_IS_NEW=false
DIST_ROWS=0
if [ -f "$DIST_CSV" ]; then
    DIST_EXISTS=true
    MTIME=$(stat -c %Y "$DIST_CSV" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then DIST_IS_NEW=true; fi
    DIST_ROWS=$(wc -l < "$DIST_CSV" 2>/dev/null || echo "0")
fi

# 2. Check Newick File
NWK_EXISTS=false
NWK_IS_NEW=false
NWK_SIZE=0
if [ -f "$NWK_FILE" ]; then
    NWK_EXISTS=true
    MTIME=$(stat -c %Y "$NWK_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then NWK_IS_NEW=true; fi
    NWK_SIZE=$(stat -c %s "$NWK_FILE" 2>/dev/null || echo "0")
fi

# 3. Check PNG File
PNG_EXISTS=false
PNG_IS_NEW=false
PNG_SIZE_KB=0
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS=true
    MTIME=$(stat -c %Y "$PNG_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then PNG_IS_NEW=true; fi
    PNG_SIZE_KB=$(du -k "$PNG_FILE" 2>/dev/null | cut -f1)
fi

# 4. Analyze R Script for Keywords
SCRIPT_EXISTS=false
SCRIPT_MODIFIED=false
HAS_APE=false
HAS_DIST=false
HAS_NJ=false
HAS_ROOT=false
HAS_OUTGROUP=false
HAS_BOOT=false

if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS=true
    MTIME=$(stat -c %Y "$SCRIPT_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then SCRIPT_MODIFIED=true; fi
    
    # Exclude comments to strictly check executed code
    CODE_ONLY=$(grep -v '^\s*#' "$SCRIPT_FILE" 2>/dev/null)
    
    echo "$CODE_ONLY" | grep -qi "ape" && HAS_APE=true
    echo "$CODE_ONLY" | grep -qi "dist.dna" && HAS_DIST=true
    echo "$CODE_ONLY" | grep -qiE "\bnj\(|\bbionj\(" && HAS_NJ=true
    echo "$CODE_ONLY" | grep -qi "root(" && HAS_ROOT=true
    echo "$CODE_ONLY" | grep -qi "No305" && HAS_OUTGROUP=true
    echo "$CODE_ONLY" | grep -qi "boot.phylo" && HAS_BOOT=true
fi

# Check if RStudio is running
RSTUDIO_RUNNING=false
if pgrep -f "rstudio" > /dev/null 2>&1; then
    RSTUDIO_RUNNING=true
fi

# Export JSON mapping
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "dist_csv_exists": $DIST_EXISTS,
    "dist_csv_is_new": $DIST_IS_NEW,
    "dist_csv_rows": $DIST_ROWS,
    "nwk_exists": $NWK_EXISTS,
    "nwk_is_new": $NWK_IS_NEW,
    "nwk_size_bytes": $NWK_SIZE,
    "png_exists": $PNG_EXISTS,
    "png_is_new": $PNG_IS_NEW,
    "png_size_kb": $PNG_SIZE_KB,
    "script_exists": $SCRIPT_EXISTS,
    "script_modified": $SCRIPT_MODIFIED,
    "has_ape": $HAS_APE,
    "has_dist_dna": $HAS_DIST,
    "has_nj": $HAS_NJ,
    "has_root": $HAS_ROOT,
    "has_outgroup": $HAS_OUTGROUP,
    "has_boot_phylo": $HAS_BOOT,
    "rstudio_running": $RSTUDIO_RUNNING,
    "task_start_time": $TASK_START
}
EOF

# Safely copy to standard path
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="