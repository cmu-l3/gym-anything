#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up NYC LL97 Compliance Task ==="

# Record start time for anti-gaming verification
echo $(date +%s) > /tmp/task_start_time.txt

# Clean environment
cleanup_temp_files
kill_onlyoffice ga
sleep 1

# Setup directories
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
DOCS_DIR="/home/ga/Documents"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# 1. Create the statutory limits text file
LIMITS_PATH="$DOCS_DIR/ll97_limits.txt"
cat > "$LIMITS_PATH" << 'EOF'
NEW YORK CITY LOCAL LAW 97 STATUTORY GHG LIMITS (2024-2029)
------------------------------------------------------------
Property Type             | Limit (tCO2e / sqft)
------------------------------------------------------------
Multifamily Housing       | 0.00675
Office                    | 0.00846
Retail Store              | 0.01181
Hotel                     | 0.00987

PENALTY RATE: $268 per metric ton of CO2e over the allowed limit.
EOF
chown ga:ga "$LIMITS_PATH"

# 2. Generate the portfolio dataset (deterministic using Python)
CSV_PATH="$WORKSPACE_DIR/nyc_ll84_portfolio.csv"
cat > /tmp/create_ll97_data.py << 'PYEOF'
import csv
import random

# Fixed seed for deterministic dataset generation
random.seed(42)

ptypes = {
    "Multifamily Housing": 0.00675,
    "Office": 0.00846,
    "Retail Store": 0.01181,
    "Hotel": 0.00987
}

with open("/home/ga/Documents/Spreadsheets/nyc_ll84_portfolio.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow([
        "Property_ID", 
        "Property_Name", 
        "Property_Type", 
        "Gross_Floor_Area_sqft", 
        "Total_GHG_Emissions_tCO2e", 
        "Energy_Star_Score"
    ])
    
    for i in range(1, 151):
        ptype = random.choice(list(ptypes.keys()))
        limit = ptypes[ptype]
        
        # Area from 50k to 1.5M sq ft
        sqft = random.randint(50000, 1500000)
        
        allowed = sqft * limit
        
        # Make roughly 55% of the buildings non-compliant (over limit)
        if random.random() < 0.55:
            # Over limit (between 5% and 60% over)
            emissions = allowed * random.uniform(1.05, 1.60)
        else:
            # Under limit (compliant)
            emissions = allowed * random.uniform(0.40, 0.95)
            
        writer.writerow([
            f"NYC-{10000+i}",
            f"{ptype.split()[0]} Prop {i}",
            ptype,
            sqft,
            round(emissions, 2),
            random.randint(40, 99)
        ])
PYEOF

python3 /tmp/create_ll97_data.py
chown ga:ga "$CSV_PATH"

# 3. Launch OnlyOffice with the CSV loaded
echo "Launching ONLYOFFICE with the portfolio data..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$CSV_PATH' > /tmp/onlyoffice_launch.log 2>&1 &"

# Wait for window and maximize
wait_for_window "ONLYOFFICE" 30
sleep 2

WID=$(get_onlyoffice_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="