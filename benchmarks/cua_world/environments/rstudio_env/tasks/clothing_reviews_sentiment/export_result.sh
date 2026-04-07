#!/bin/bash
echo "=== Exporting Sentiment Analysis Results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
take_screenshot /tmp/task_end.png

OUTPUT_DIR="/home/ga/RProjects/output"
SUMMARY_CSV="$OUTPUT_DIR/class_sentiment_summary.csv"
PLOT_PNG="$OUTPUT_DIR/dresses_sentiment_dist.png"
NEG_CSV="$OUTPUT_DIR/dresses_negative_words.csv"
SCRIPT_PATH="/home/ga/RProjects/sentiment_analysis.R"

# --- Analyze Summary CSV ---
SUMMARY_EXISTS=false
SUMMARY_NEW=false
SUMMARY_COLS_VALID=false
SUMMARY_DRESSES_FOUND=false
SUMMARY_SCORE_VALID=false

if [ -f "$SUMMARY_CSV" ]; then
    SUMMARY_EXISTS=true
    if [ $(stat -c %Y "$SUMMARY_CSV") -gt "$TASK_START" ]; then
        SUMMARY_NEW=true
    fi
    
    # Check content using python
    read -r SUMMARY_COLS_VALID SUMMARY_DRESSES_FOUND SUMMARY_SCORE_VALID <<< $(python3 -c "
import pandas as pd
try:
    df = pd.read_csv('$SUMMARY_CSV')
    cols = [c.lower() for c in df.columns]
    
    # Check columns (need class name and some sentiment metric)
    has_class = any('class' in c for c in cols)
    has_score = any('sentiment' in c or 'score' in c or 'mean' in c or 'value' in c for c in cols)
    cols_valid = 'true' if (has_class and has_score) else 'false'
    
    # Check for 'Dresses' class
    # Assumes class column is the one with 'class' in name, or first string column
    class_col = next((c for c in df.columns if 'class' in c.lower()), None)
    dresses_found = 'false'
    score_valid = 'false'
    
    if class_col:
        vals = df[class_col].astype(str).str.lower().values
        if 'dresses' in vals:
            dresses_found = 'true'
            
    # Check sentiment range (usually 0 to 5 for this data with AFINN)
    # Assumes score column is numeric
    score_col = next((c for c in df.columns if 'sentiment' in c.lower() or 'mean' in c.lower()), None)
    if score_col:
        mean_score = df[score_col].mean()
        if 0 < mean_score < 5:
            score_valid = 'true'

    print(f'{cols_valid} {dresses_found} {score_valid}')
except:
    print('false false false')
")
fi

# --- Analyze Plot PNG ---
PLOT_EXISTS=false
PLOT_NEW=false
PLOT_SIZE_KB=0

if [ -f "$PLOT_PNG" ]; then
    PLOT_EXISTS=true
    if [ $(stat -c %Y "$PLOT_PNG") -gt "$TASK_START" ]; then
        PLOT_NEW=true
    fi
    PLOT_SIZE_KB=$(du -k "$PLOT_PNG" | cut -f1)
fi

# --- Analyze Negative Words CSV ---
NEG_EXISTS=false
NEG_NEW=false
NEG_CONTENT_VALID=false

if [ -f "$NEG_CSV" ]; then
    NEG_EXISTS=true
    if [ $(stat -c %Y "$NEG_CSV") -gt "$TASK_START" ]; then
        NEG_NEW=true
    fi
    
    # Check for known negative words
    NEG_CONTENT_VALID=$(python3 -c "
import pandas as pd
try:
    df = pd.read_csv('$NEG_CSV')
    # Get all text content
    text = ' '.join(df.astype(str).values.flatten()).lower()
    keywords = ['small', 'tight', 'short', 'thin', 'cheap', 'poor', 'returned', 'disappointed', 'fabric', 'material']
    # Pass if at least 2 keywords found
    found = sum(1 for k in keywords if k in text)
    print('true' if found >= 2 else 'false')
except:
    print('false')
")
fi

# --- Analyze Script ---
SCRIPT_MODIFIED=false
USED_TIDYTEXT=false

if [ -f "$SCRIPT_PATH" ]; then
    if [ $(stat -c %Y "$SCRIPT_PATH") -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED=true
    fi
    if grep -q "unnest_tokens" "$SCRIPT_PATH" || grep -q "tidytext" "$SCRIPT_PATH"; then
        USED_TIDYTEXT=true
    fi
fi

# Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "summary_exists": $SUMMARY_EXISTS,
    "summary_new": $SUMMARY_NEW,
    "summary_cols_valid": $SUMMARY_COLS_VALID,
    "summary_dresses_found": $SUMMARY_DRESSES_FOUND,
    "summary_score_valid": $SUMMARY_SCORE_VALID,
    "plot_exists": $PLOT_EXISTS,
    "plot_new": $PLOT_NEW,
    "plot_size_kb": $PLOT_SIZE_KB,
    "neg_exists": $NEG_EXISTS,
    "neg_new": $NEG_NEW,
    "neg_content_valid": $NEG_CONTENT_VALID,
    "script_modified": $SCRIPT_MODIFIED,
    "used_tidytext": $USED_TIDYTEXT
}
EOF

echo "Result JSON created:"
cat /tmp/task_result.json