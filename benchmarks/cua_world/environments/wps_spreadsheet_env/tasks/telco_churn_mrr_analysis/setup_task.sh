#!/bin/bash
echo "=== Setting up telco_churn_mrr_analysis task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Target file
CSV_FILE="/home/ga/Documents/telco_customer_churn.csv"
rm -f "$CSV_FILE" 2>/dev/null || true
rm -f "/home/ga/Documents/churn_analysis.xlsx" 2>/dev/null || true

# Download the real IBM Telco Customer Churn dataset
echo "Attempting to download real IBM Telco Customer Churn dataset..."
curl -sL "https://raw.githubusercontent.com/IBM/telco-customer-churn-on-icp4d/master/data/Telco-Customer-Churn.csv" -o "$CSV_FILE" 2>/dev/null || true

# Fallback: if download fails or is incomplete (offline environment), generate a realistic subset
if [ ! -f "$CSV_FILE" ] || [ $(stat -c%s "$CSV_FILE") -lt 1000 ]; then
    echo "Download failed or unavailable. Generating robust offline data subset..."
    python3 << 'PYEOF'
import csv
import random

headers = ["customerID","gender","SeniorCitizen","Partner","Dependents","tenure",
           "PhoneService","MultipleLines","InternetService","OnlineSecurity",
           "OnlineBackup","DeviceProtection","TechSupport","StreamingTV",
           "StreamingMovies","Contract","PaperlessBilling","PaymentMethod",
           "MonthlyCharges","TotalCharges","Churn"]

contracts = ["Month-to-month", "One year", "Two year"]
internet = ["DSL", "Fiber optic", "No"]
yes_no = ["Yes", "No"]

data = []
# Create ~150 rows of realistic synthesized data based on IBM dataset distributions
for i in range(150):
    cid = f"{random.randint(1000,9999)}-{chr(random.randint(65,90))}{chr(random.randint(65,90))}{chr(random.randint(65,90))}{chr(random.randint(65,90))}{chr(random.randint(65,90))}"
    contract = random.choices(contracts, weights=[0.55, 0.21, 0.24])[0]
    int_srv = random.choices(internet, weights=[0.34, 0.44, 0.22])[0]
    
    # Logic correlating tenure, charges, and churn (realistic bounds)
    if contract == "Month-to-month":
        tenure = random.randint(1, 24)
        churn = random.choices(yes_no, weights=[0.45, 0.55])[0]
    else:
        tenure = random.randint(12, 72)
        churn = random.choices(yes_no, weights=[0.10, 0.90])[0]
        
    if int_srv == "Fiber optic":
        monthly = round(random.uniform(70.0, 115.0), 2)
    elif int_srv == "DSL":
        monthly = round(random.uniform(45.0, 70.0), 2)
    else:
        monthly = round(random.uniform(19.0, 25.0), 2)
        
    total = round(monthly * tenure, 2)
    
    row = [
        cid, random.choice(["Male", "Female"]), random.choice(["0", "1"]), 
        random.choice(yes_no), random.choice(yes_no), str(tenure),
        random.choice(yes_no), random.choice(["No phone service", "No", "Yes"]),
        int_srv, random.choice(["No internet service", "No", "Yes"]),
        random.choice(["No internet service", "No", "Yes"]), random.choice(["No internet service", "No", "Yes"]),
        random.choice(["No internet service", "No", "Yes"]), random.choice(["No internet service", "No", "Yes"]),
        random.choice(["No internet service", "No", "Yes"]), contract, random.choice(yes_no),
        random.choice(["Electronic check", "Mailed check", "Bank transfer (automatic)", "Credit card (automatic)"]),
        str(monthly), str(total), churn
    ]
    data.append(row)

with open("/home/ga/Documents/telco_customer_churn.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(headers)
    writer.writerows(data)
PYEOF
fi

chown ga:ga "$CSV_FILE"

# Start WPS Spreadsheet
if ! pgrep -f "et" > /dev/null; then
    echo "Starting WPS Spreadsheet..."
    su - ga -c "DISPLAY=:1 et &"
    sleep 5
fi

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "WPS Spreadsheets\|et"; then
        break
    fi
    sleep 1
done

# Maximize and focus the window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a :ACTIVE: 2>/dev/null || true

# Dismiss startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="