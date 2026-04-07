#!/bin/bash
echo "=== Exporting Portfolio Optimization Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
take_screenshot /tmp/task_end.png

WEIGHTS_CSV="/home/ga/RProjects/output/min_var_weights.csv"
SUMMARY_CSV="/home/ga/RProjects/output/returns_summary.csv"
PLOT_PNG="/home/ga/RProjects/output/efficient_frontier.png"

# 1. Check file existence and timestamps
WEIGHTS_EXISTS=false
WEIGHTS_IS_NEW=false
if [ -f "$WEIGHTS_CSV" ]; then
    WEIGHTS_EXISTS=true
    MTIME=$(stat -c %Y "$WEIGHTS_CSV" 2>/dev/null || echo "0")
    [ "$MTIME" -gt "$TASK_START" ] && WEIGHTS_IS_NEW=true
fi

SUMMARY_EXISTS=false
if [ -f "$SUMMARY_CSV" ]; then
    SUMMARY_EXISTS=true
fi

PLOT_EXISTS=false
PLOT_SIZE_KB=0
if [ -f "$PLOT_PNG" ]; then
    PLOT_EXISTS=true
    PLOT_SIZE_KB=$(du -k "$PLOT_PNG" 2>/dev/null | cut -f1)
fi

# 2. Perform Quantitative Verification inside the container using R
# We calculate the TRUE Global Min Var and compare the user's result
# This avoids doing complex math in the python verifier

echo "Running internal verification script..."
R --vanilla --slave << 'REOF' > /tmp/verification_metrics.json
library(jsonlite)

result <- list(
    valid_format = FALSE,
    weights_sum = 0,
    min_weight = -1,
    user_variance = 999,
    opt_variance = 0,
    variance_diff_pct = 999
)

tryCatch({
    # 1. Load Ground Truth Data
    data(EuStockMarkets)
    prices <- as.matrix(EuStockMarkets)
    # Calculate log returns
    log_returns <- diff(log(prices))
    # Covariance matrix (annualized 260 days)
    # Note: Optimization result is scale-invariant, but we stick to raw for precision
    cov_mat <- cov(log_returns) * 260
    
    # 2. Calculate True Global Min Var (Analytical solution for unconstrained, or QuadProg for constrained)
    # Since we need long-only (w >= 0), we use quadprog
    library(quadprog)
    
    n_assets <- 4
    Dmat <- cov_mat
    dvec <- rep(0, n_assets)
    # Constraints: sum(w)=1, w>=0
    # Amat^T * w >= bvec
    # 1. sum(w) = 1  ->  c(1,1,1,1) * w = 1 (handled as >=1 and <=1 usually, or equality in solve.QP)
    # 2. w >= 0      ->  diag(1) * w >= 0
    
    Amat <- cbind(rep(1, n_assets), diag(n_assets))
    bvec <- c(1, rep(0, n_assets))
    
    # solve.QP solves min(-d^T b + 1/2 b^T D b)
    # meq=1 means first constraint is equality
    opt <- solve.QP(Dmat, dvec, Amat, bvec, meq=1)
    
    true_min_var <- opt$value * 2 # solve.QP minimizes 1/2 x'Dx
    result$opt_variance <- true_min_var

    # 3. Load User Weights
    user_file <- "/home/ga/RProjects/output/min_var_weights.csv"
    if(file.exists(user_file)) {
        user_w <- read.csv(user_file)
        
        # Normalize column names
        colnames(user_w) <- tolower(colnames(user_w))
        
        # Check structure
        if("weight" %in% colnames(user_w) && nrow(user_w) == 4) {
             # Align weights to indices (DAX, SMI, CAC, FTSE)
             # Assuming user output might be ordered differently, try to match by name if possible
             # If 'index' col exists, use it. Otherwise assume standard order.
             
             w_vec <- rep(0, 4)
             names(w_vec) <- colnames(prices) # DAX, SMI, CAC, FTSE
             
             if("index" %in% colnames(user_w)) {
                 for(i in 1:4) {
                     idx_name <- user_w$index[i]
                     # Fuzzy match or exact match
                     for(real_name in names(w_vec)) {
                         if(grepl(real_name, idx_name, ignore.case=TRUE)) {
                             w_vec[real_name] <- user_w$weight[i]
                         }
                     }
                 }
             } else {
                 # Fallback to row order
                 w_vec <- user_w$weight
             }
             
             result$valid_format <- TRUE
             result$weights_sum <- sum(w_vec)
             result$min_weight <- min(w_vec)
             
             # Calculate user portfolio variance
             # var = w' S w
             user_var <- as.numeric(t(w_vec) %*% cov_mat %*% w_vec)
             result$user_variance <- user_var
             
             # Calculate percentage difference from optimal
             if(true_min_var > 0) {
                 result$variance_diff_pct <- abs(user_var - true_min_var) / true_min_var * 100
             }
        }
    }
}, error = function(e) {
    # output error to stderr but keep json valid
    message(paste("Error in verification:", e$message))
})

cat(toJSON(result, auto_unbox=TRUE))
REOF

# 3. Combine results
VERIFICATION_JSON=$(cat /tmp/verification_metrics.json 2>/dev/null || echo "{}")

# Create final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "weights_exists": $WEIGHTS_EXISTS,
    "weights_is_new": $WEIGHTS_IS_NEW,
    "summary_exists": $SUMMARY_EXISTS,
    "plot_exists": $PLOT_EXISTS,
    "plot_size_kb": $PLOT_SIZE_KB,
    "verification_metrics": $VERIFICATION_JSON
}
EOF

# Move to safe location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="