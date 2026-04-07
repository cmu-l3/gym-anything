#!/bin/bash
echo "=== Exporting LaLonde Task Results ==="

source /workspace/scripts/task_utils.sh

# 1. timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. Define paths
OUTPUT_DIR="/home/ga/RProjects/output"
BALANCE_CSV="$OUTPUT_DIR/lalonde_balance_table.csv"
EFFECTS_CSV="$OUTPUT_DIR/lalonde_treatment_effects.csv"
PLOT_PNG="$OUTPUT_DIR/lalonde_love_plot.png"
SCRIPT_FILE="/home/ga/RProjects/output/lalonde_analysis.R" # User might save here
SCRIPT_FILE_ORIG="/home/ga/RProjects/lalonde_analysis.R" # Or overwrite original

# 3. Check Files and Collect Metadata

# Function to check file status
check_file() {
    local fpath=$1
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath")
        local size=$(stat -c %s "$fpath")
        local is_new="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            is_new="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"is_new\": $is_new, \"path\": \"$fpath\"}"
    else
        echo "{\"exists\": false, \"size\": 0, \"is_new\": false, \"path\": \"$fpath\"}"
    fi
}

BAL_STATUS=$(check_file "$BALANCE_CSV")
EFF_STATUS=$(check_file "$EFFECTS_CSV")
PLOT_STATUS=$(check_file "$PLOT_PNG")

# Check script in both possible locations
if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_STATUS=$(check_file "$SCRIPT_FILE")
elif [ -f "$SCRIPT_FILE_ORIG" ]; then
    SCRIPT_STATUS=$(check_file "$SCRIPT_FILE_ORIG")
    # Copy to output dir for verifier convenience if it's the one modified
    cp "$SCRIPT_FILE_ORIG" "$OUTPUT_DIR/lalonde_analysis_submitted.R" 2>/dev/null || true
else
    SCRIPT_STATUS="{\"exists\": false}"
fi

# 4. R-based Sanity Check (Content Verification inside container)
# We run a small R script to validate CSV structure since bash parsing is fragile
R_CHECK_RESULT=$(R --vanilla --slave << 'R_EOF'
tryCatch({
    bal_path <- "/home/ga/RProjects/output/lalonde_balance_table.csv"
    eff_path <- "/home/ga/RProjects/output/lalonde_treatment_effects.csv"
    
    res <- list(valid_bal=FALSE, valid_eff=FALSE, smd_improved=FALSE, has_naive=FALSE, has_matched=FALSE)
    
    if(file.exists(bal_path)) {
        bal <- read.csv(bal_path)
        # Look for SMD/Mean Diff columns
        cols <- tolower(names(bal))
        if (any(grepl("unmatched|all|unadj", cols)) && any(grepl("matched|adj", cols))) {
             res$valid_bal <- TRUE
             # Try to check improvement if numeric columns found
             # This is a heuristic; python verifier does the real math
        }
    }
    
    if(file.exists(eff_path)) {
        eff <- read.csv(eff_path)
        res$valid_eff <- nrow(eff) >= 2
        
        # Check for numeric estimates
        # Simple string matching for method names
        vals <- as.character(eff[[1]]) # assume first col is labels if not named
        if(length(names(eff)) > 0) {
            # Try to find specific columns
            txt <- paste(unlist(eff), collapse=" ")
            if(grepl("Naive|Unadjusted|Raw", txt, ignore.case=TRUE)) res$has_naive <- TRUE
            if(grepl("Match|NN|Full", txt, ignore.case=TRUE)) res$has_matched <- TRUE
        }
    }
    
    cat(jsonlite::toJSON(res, auto_unbox=TRUE))
}, error=function(e) {
    cat('{"error": "R check failed"}')
})
R_EOF
)

# 5. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Create JSON Report
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "balance_csv": $BAL_STATUS,
    "effects_csv": $EFF_STATUS,
    "plot_png": $PLOT_STATUS,
    "script": $SCRIPT_STATUS,
    "r_check": ${R_CHECK_RESULT:-"{}"},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# 7. Copy deliverables to tmp for easy extraction by verifier.py
cp "$BALANCE_CSV" /tmp/submitted_balance.csv 2>/dev/null || true
cp "$EFFECTS_CSV" /tmp/submitted_effects.csv 2>/dev/null || true
cp "$PLOT_PNG" /tmp/submitted_plot.png 2>/dev/null || true
if [ -f "$OUTPUT_DIR/lalonde_analysis_submitted.R" ]; then
    cp "$OUTPUT_DIR/lalonde_analysis_submitted.R" /tmp/submitted_script.R
elif [ -f "$SCRIPT_FILE" ]; then
    cp "$SCRIPT_FILE" /tmp/submitted_script.R
else
    cp "$SCRIPT_FILE_ORIG" /tmp/submitted_script.R 2>/dev/null || true
fi

chmod 644 /tmp/submitted_* 2>/dev/null || true

echo "=== Export Complete ==="