#!/bin/bash
set -e
echo "=== Setting up product_segmentation_clustering task ==="

# Define paths
TASK_DIR="C:\\Users\\Docker\\Desktop\\PowerBITasks"
DATA_FILE="$TASK_DIR\\sales_data.csv"
TARGET_FILE="C:\\Users\\Docker\\Desktop\\Product_Segmentation.pbix"

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous run artifacts
if [ -f "$TARGET_FILE" ]; then
    rm "$TARGET_FILE"
    echo "Removed previous target file."
fi

# 3. Ensure Power BI is not running initially to start clean
if pgrep -f "PBIDesktop" > /dev/null; then
    echo "Closing existing Power BI instances..."
    powershell -Command "Stop-Process -Name PBIDesktop -Force -ErrorAction SilentlyContinue"
    sleep 2
fi

# 4. Verify data source exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Data file $DATA_FILE not found!"
    # In a real scenario, we might download it here, but the env provides it.
    # We'll just touch it to ensure it exists for the script
    mkdir -p "$(dirname "$DATA_FILE")"
    echo "Product_ID,Sale_Date,Sales_Amount,Quantity_Sold,Product_Category" > "$DATA_FILE"
    echo "P001,2023-01-01,100,10,Widgets" >> "$DATA_FILE"
fi

# 5. Start Power BI Desktop (Maximize window for agent visibility)
echo "Starting Power BI Desktop..."
# Note: In this environment, we often let the agent start it or start it empty.
# We will start it empty here to save the agent time.
powershell -Command "Start-Process 'C:\\Program Files\\Microsoft Power BI Desktop\\bin\\PBIDesktop.exe' -WindowStyle Maximized"

# Wait for window to appear
echo "Waiting for Power BI to load..."
for i in {1..60}; do
    if powershell -Command "Get-Process PBIDesktop -ErrorAction SilentlyContinue" > /dev/null; then
        break
    fi
    sleep 1
done
sleep 10 # Allow UI to fully render

# 6. Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="