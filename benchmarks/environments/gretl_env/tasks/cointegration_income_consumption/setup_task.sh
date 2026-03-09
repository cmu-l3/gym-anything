#!/bin/bash
echo "=== Setting up cointegration_income_consumption task ==="

source /workspace/scripts/task_utils.sh

# Ensure directories exist
mkdir -p /home/ga/Documents/gretl_data
mkdir -p /home/ga/Documents/gretl_output

# Download FRED data: Real Personal Consumption Expenditures (PCEC96)
echo "Downloading PCEC96 (Real Personal Consumption Expenditures) from FRED..."
PCEC96_URL="https://fred.stlouisfed.org/graph/fredgraph.csv?id=PCEC96"
PCEC96_DEST="/home/ga/Documents/gretl_data/PCEC96.csv"

if [ ! -f "$PCEC96_DEST" ]; then
    wget -q -O "$PCEC96_DEST" "$PCEC96_URL" 2>&1
    if [ $? -ne 0 ]; then
        # Try curl as fallback
        curl -s -o "$PCEC96_DEST" "$PCEC96_URL" 2>&1
    fi
fi

if [ -f "$PCEC96_DEST" ] && [ -s "$PCEC96_DEST" ]; then
    echo "PCEC96 downloaded: $(wc -l < $PCEC96_DEST) rows"
else
    echo "WARNING: PCEC96 download may have failed" >&2
fi

# Download FRED data: Real Disposable Personal Income (DSPIC96)
echo "Downloading DSPIC96 (Real Disposable Personal Income) from FRED..."
DSPIC96_URL="https://fred.stlouisfed.org/graph/fredgraph.csv?id=DSPIC96"
DSPIC96_DEST="/home/ga/Documents/gretl_data/DSPIC96.csv"

if [ ! -f "$DSPIC96_DEST" ]; then
    wget -q -O "$DSPIC96_DEST" "$DSPIC96_URL" 2>&1
    if [ $? -ne 0 ]; then
        curl -s -o "$DSPIC96_DEST" "$DSPIC96_URL" 2>&1
    fi
fi

if [ -f "$DSPIC96_DEST" ] && [ -s "$DSPIC96_DEST" ]; then
    echo "DSPIC96 downloaded: $(wc -l < $DSPIC96_DEST) rows"
else
    echo "WARNING: DSPIC96 download may have failed" >&2
fi

# Verify data files
echo "Data file check:"
ls -lh /home/ga/Documents/gretl_data/ 2>/dev/null || echo "No files in gretl_data directory"

# Record download/verification status
PCEC96_OK="false"
DSPIC96_OK="false"
[ -f "$PCEC96_DEST" ] && [ -s "$PCEC96_DEST" ] && PCEC96_OK="true"
[ -f "$DSPIC96_DEST" ] && [ -s "$DSPIC96_DEST" ] && DSPIC96_OK="true"

echo "$PCEC96_OK $DSPIC96_OK" > /tmp/cointegration_data_state

# Record task start timestamp
date +%s > /tmp/cointegration_start
date --iso-8601=seconds >> /tmp/cointegration_start

# Record output baseline
OUTPUT_FILE="/home/ga/Documents/gretl_output/cointegration_results.txt"
if [ -f "$OUTPUT_FILE" ]; then
    BASELINE_EXISTS="true"
    BASELINE_SIZE=$(wc -c < "$OUTPUT_FILE")
else
    BASELINE_EXISTS="false"
    BASELINE_SIZE="0"
fi
echo "$BASELINE_EXISTS $BASELINE_SIZE" > /tmp/cointegration_baseline_state

# Kill existing gretl and launch fresh
kill_gretl
sleep 1
launch_gretl
wait_for_gretl
maximize_gretl
take_screenshot "/tmp/cointegration_setup.png"

echo ""
echo "============================================================"
echo "TASK: Cointegration Analysis — Permanent Income Hypothesis"
echo "============================================================"
echo ""
echo "Gretl is running. Real US macroeconomic data from FRED has"
echo "been downloaded to /home/ga/Documents/gretl_data/:"
echo ""
echo "  PCEC96.csv  - Real Personal Consumption Expenditures"
echo "                (billions chained 2017 dollars, quarterly)"
echo "  DSPIC96.csv - Real Disposable Personal Income"
echo "                (billions chained 2017 dollars, quarterly)"
echo ""
echo "Goal: Test whether consumption and income are cointegrated."
echo "      Use Engle-Granger two-step method."
echo "      Apply log transforms: lcons = log(PCEC96), linc = log(DSPIC96)"
echo "      Run ADF unit root tests and Engle-Granger cointegration test."
echo ""
echo "Save results to: /home/ga/Documents/gretl_output/cointegration_results.txt"
echo "============================================================"
