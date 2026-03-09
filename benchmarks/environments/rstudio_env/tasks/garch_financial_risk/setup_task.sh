#!/bin/bash
echo "=== Setting up garch_financial_risk task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/RProjects/output
mkdir -p /home/ga/RProjects/datasets
chown -R ga:ga /home/ga/RProjects

# Remove stale output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/RProjects/output/spy_var_estimates.csv
rm -f /home/ga/RProjects/output/spy_backtest.csv
rm -f /home/ga/RProjects/output/spy_garch_report.png
rm -f /home/ga/RProjects/garch_analysis.R

# Install required packages
echo "Checking and installing rugarch, quantmod..."
R --vanilla --slave << 'REOF'
pkgs <- c("rugarch", "quantmod", "xts", "zoo")
for (pkg in pkgs) {
    if (!requireNamespace(pkg, quietly=TRUE)) {
        message(paste("Installing", pkg, "..."))
        install.packages(pkg, repos="https://cloud.r-project.org/", quiet=TRUE)
    } else {
        message(paste(pkg, "already available"))
    }
}
message("Package check complete")
REOF

# Download real SPY data from Yahoo Finance if not already present
SPY_CSV="/home/ga/RProjects/datasets/spy_prices.csv"
if [ ! -f "$SPY_CSV" ] || [ $(wc -l < "$SPY_CSV" 2>/dev/null || echo "0") -lt 100 ]; then
    echo "Downloading SPY price data from Yahoo Finance..."
    R --vanilla --slave << 'REOF'
tryCatch({
    library(quantmod)
    spy <- getSymbols("SPY", src="yahoo", from="2015-01-01", to="2023-12-31",
                      auto.assign=FALSE, warnings=FALSE)
    spy_df <- data.frame(
        Date = index(spy),
        Open = as.numeric(Op(spy)),
        High = as.numeric(Hi(spy)),
        Low = as.numeric(Lo(spy)),
        Close = as.numeric(Cl(spy)),
        Volume = as.numeric(Vo(spy)),
        Adjusted = as.numeric(Ad(spy))
    )
    write.csv(spy_df, "/home/ga/RProjects/datasets/spy_prices.csv", row.names=FALSE)
    message(paste("Downloaded", nrow(spy_df), "days of SPY data"))
}, error = function(e) {
    message(paste("Yahoo download failed:", e$message))
    # Fallback: try alternative source
    tryCatch({
        url <- "https://query1.finance.yahoo.com/v7/finance/download/SPY?period1=1420070400&period2=1703980800&interval=1d&events=history"
        download.file(url, "/tmp/spy_raw.csv", quiet=TRUE, method="wget")
        raw <- read.csv("/tmp/spy_raw.csv")
        names(raw)[names(raw)=="Adj.Close"] <- "Adjusted"
        write.csv(raw, "/home/ga/RProjects/datasets/spy_prices.csv", row.names=FALSE)
        message(paste("Downloaded via URL:", nrow(raw), "rows"))
    }, error = function(e2) {
        message(paste("Fallback also failed:", e2$message))
    })
})
REOF
fi

# Verify SPY data exists
if [ ! -f "$SPY_CSV" ] || [ $(wc -l < "$SPY_CSV" 2>/dev/null || echo "0") -lt 100 ]; then
    echo "ERROR: Could not download SPY data. Please check network connectivity."
    exit 1
fi

SPY_ROWS=$(wc -l < "$SPY_CSV")
echo "SPY data verified: $SPY_ROWS rows (including header)"
chown ga:ga "$SPY_CSV"

# Create starter R script BEFORE recording timestamp
# (mtime of starter < task_start; agent must modify it for credit)
cat > /home/ga/RProjects/garch_analysis.R << 'RSCRIPT'
# GARCH Volatility and VaR Analysis — SPY ETF
# Financial Quantitative Analysis
#
# Dataset: /home/ga/RProjects/datasets/spy_prices.csv
# Key packages: rugarch
#
# TODO: Implement the GARCH(1,1) analysis pipeline:
# 1. Load SPY data, compute log returns
# 2. Fit GARCH(1,1) model using rugarch (ugarchspec + ugarchfit)
# 3. Extract conditional volatility and compute VaR at 95% and 99%
# 4. Write spy_var_estimates.csv
# 5. Perform Kupiec POF backtest and write spy_backtest.csv
# 6. Create 3-panel figure: spy_garch_report.png

RSCRIPT
chown ga:ga /home/ga/RProjects/garch_analysis.R

# Record task start timestamp AFTER starter creation (anti-gaming: starter mtime <= task_start)
date +%s > /tmp/garch_financial_risk_start_ts

# Record initial state
echo '{"var_csv_exists": false, "backtest_csv_exists": false, "plot_exists": false}' > /tmp/garch_financial_risk_initial.json

# Ensure RStudio is running
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/garch_analysis.R &"
    sleep 10
else
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/garch_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2
take_screenshot /tmp/garch_financial_risk_start.png

echo "=== Setup Complete ==="
echo "Dataset: /home/ga/RProjects/datasets/spy_prices.csv (real SPY ETF data)"
echo "Task: GARCH(1,1) volatility model + VaR computation"
echo "Outputs expected in: /home/ga/RProjects/output/"
