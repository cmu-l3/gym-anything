#!/bin/bash
echo "=== Setting up Cox Regression Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create JASP documents directory
mkdir -p /home/ga/Documents/JASP

# Download real Telco Churn dataset
# Source: IBM / Kaggle public domain sample
DATASET_PATH="/home/ga/Documents/JASP/TelcoChurn.csv"
DATASET_URL="https://raw.githubusercontent.com/IBM/telco-customer-churn-on-icp4d/master/data/Telco-Customer-Churn.csv"

echo "Downloading dataset..."
if curl -L -o "$DATASET_PATH" "$DATASET_URL"; then
    echo "Download complete."
else
    echo "ERROR: Failed to download dataset."
    # Fallback to creating a dummy file if network fails (prevent complete block, though verification will fail)
    echo "customerID,gender,SeniorCitizen,Partner,Dependents,tenure,PhoneService,MultipleLines,InternetService,OnlineSecurity,OnlineBackup,DeviceProtection,TechSupport,StreamingTV,StreamingMovies,Contract,PaperlessBilling,PaymentMethod,MonthlyCharges,TotalCharges,Churn" > "$DATASET_PATH"
fi

# Ensure permissions
chown ga:ga "$DATASET_PATH"
chmod 644 "$DATASET_PATH"

# Kill any existing JASP instances
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
pkill -f "JASP" 2>/dev/null || true
sleep 2

# Start JASP
# Using the system-wide launcher created in environment setup
echo "Starting JASP..."
su - ga -c "setsid /usr/local/bin/launch-jasp > /tmp/jasp.log 2>&1 &"

# Wait for JASP window
echo "Waiting for JASP window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
        echo "JASP window found."
        break
    fi
    sleep 1
done

# Maximize JASP window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="