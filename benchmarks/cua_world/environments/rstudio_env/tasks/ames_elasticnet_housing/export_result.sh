#!/bin/bash
echo "=== Exporting Ames Housing Task Results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUT_DIR="/home/ga/RProjects/output"
SCRIPT_PATH="/home/ga/RProjects/ames_elasticnet.R"

take_screenshot /tmp/task_final.png

# Initialize result variables
PREPROC_EXISTS=false
PREPROC_ROWS=0
MODEL_EXISTS=false
MODEL_ROWS=0
RMSE_VALID=false
SPARSITY_VALID=false
PREDICTORS_EXISTS=false
HAS_KEY_PREDICTOR=false
PLOT_EXISTS=false
PLOT_SIZE_KB=0
SCRIPT_MODIFIED=false
SCRIPT_HAS_GLMNET=false

# 1. Check Preprocessing Summary
if [ -f "$OUT_DIR/ames_preprocessing_summary.csv" ]; then
    MTIME=$(stat -c %Y "$OUT_DIR/ames_preprocessing_summary.csv")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        PREPROC_EXISTS=true
        PREPROC_ROWS=$(awk 'END {print NR}' "$OUT_DIR/ames_preprocessing_summary.csv")
    fi
fi

# 2. Check Model Comparison
if [ -f "$OUT_DIR/ames_model_comparison.csv" ]; then
    MTIME=$(stat -c %Y "$OUT_DIR/ames_model_comparison.csv")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        MODEL_EXISTS=true
        MODEL_ROWS=$(awk 'END {print NR}' "$OUT_DIR/ames_model_comparison.csv")
        
        # Verify RMSE range and Sparsity logic using Python
        python3 << EOF > /tmp/model_check.txt
import pandas as pd
try:
    df = pd.read_csv("$OUT_DIR/ames_model_comparison.csv")
    
    # Check RMSE plausibility ($15k - $45k)
    rmse_valid = False
    if 'cv_rmse_min' in df.columns:
        min_rmse = df['cv_rmse_min'].min()
        max_rmse = df['cv_rmse_min'].max()
        if 15000 < min_rmse < 45000:
            rmse_valid = True
            
    # Check sparsity (Ridge should have most nonzero, Lasso least/comparable)
    sparsity_valid = False
    if 'n_nonzero_coefs' in df.columns and 'model' in df.columns:
        ridge = df[df['model'].str.lower().str.contains('ridge')]['n_nonzero_coefs'].max()
        lasso = df[df['model'].str.lower().str.contains('lasso')]['n_nonzero_coefs'].min()
        if ridge >= lasso:
            sparsity_valid = True
            
    print(f"{str(rmse_valid).lower()},{str(sparsity_valid).lower()}")
except:
    print("false,false")
EOF
        read RMSE_VALID_STR SPARSITY_VALID_STR < <(cat /tmp/model_check.txt | tr ',' ' ')
        RMSE_VALID=$RMSE_VALID_STR
        SPARSITY_VALID=$SPARSITY_VALID_STR
    fi
fi

# 3. Check Top Predictors
if [ -f "$OUT_DIR/ames_top_predictors.csv" ]; then
    MTIME=$(stat -c %Y "$OUT_DIR/ames_top_predictors.csv")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        PREDICTORS_EXISTS=true
        # Check for key variables
        if grep -Ei "Overall_Qual|Gr_Liv_Area" "$OUT_DIR/ames_top_predictors.csv" > /dev/null; then
            HAS_KEY_PREDICTOR=true
        fi
    fi
fi

# 4. Check Diagnostic Plot
if [ -f "$OUT_DIR/ames_elasticnet_diagnostics.png" ]; then
    MTIME=$(stat -c %Y "$OUT_DIR/ames_elasticnet_diagnostics.png")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        PLOT_EXISTS=true
        PLOT_SIZE_KB=$(du -k "$OUT_DIR/ames_elasticnet_diagnostics.png" | cut -f1)
    fi
fi

# 5. Check Script
if [ -f "$SCRIPT_PATH" ]; then
    MTIME=$(stat -c %Y "$SCRIPT_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED=true
        if grep -q "glmnet" "$SCRIPT_PATH"; then
            SCRIPT_HAS_GLMNET=true
        fi
    fi
fi

# Build JSON result
cat << EOF > /tmp/task_result.json
{
    "task_start": $TASK_START,
    "preproc_exists": $PREPROC_EXISTS,
    "preproc_rows": $PREPROC_ROWS,
    "model_exists": $MODEL_EXISTS,
    "model_rows": $MODEL_ROWS,
    "rmse_valid": $RMSE_VALID,
    "sparsity_valid": $SPARSITY_VALID,
    "predictors_exists": $PREDICTORS_EXISTS,
    "has_key_predictor": $HAS_KEY_PREDICTOR,
    "plot_exists": $PLOT_EXISTS,
    "plot_size_kb": $PLOT_SIZE_KB,
    "script_modified": $SCRIPT_MODIFIED,
    "script_has_glmnet": $SCRIPT_HAS_GLMNET
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="