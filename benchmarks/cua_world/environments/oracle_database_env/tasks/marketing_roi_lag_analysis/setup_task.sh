#!/bin/bash
set -e

echo "=== Setting up Marketing ROI Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Ensure Oracle is ready
echo "Waiting for Oracle..."
if ! wait_for_oracle_ready 60; then
    # Fallback wait if function not available
    sleep 10
fi

# Install numpy/pandas for data generation if needed (environment has python3-pip)
if ! python3 -c "import pandas" 2>/dev/null; then
    echo "Installing pandas for data generation..."
    pip3 install pandas numpy oracledb --break-system-packages 2>/dev/null || true
fi

# Clean previous runs
rm -f /var/lib/oracle/roi_ground_truth.json
oracle_query "DROP VIEW CAMPAIGN_ROI_ANALYSIS;" "hr" >/dev/null 2>&1 || true
oracle_query "DROP TABLE RAW_SALES;" "hr" >/dev/null 2>&1 || true
oracle_query "DROP TABLE RAW_AD_SPEND;" "hr" >/dev/null 2>&1 || true

# Generate Data and Ground Truth using Python
echo "Generating synthetic marketing data..."
python3 << 'PYEOF'
import numpy as np
import pandas as pd
import oracledb
import json
import datetime

# Setup
np.random.seed(42)
regions = [1, 2, 3, 4, 5]
dates = pd.date_range(start='2024-01-01', end='2025-12-31', freq='D')
months = pd.date_range(start='2024-01-01', end='2025-12-31', freq='ME') # Month End

spend_data = []
sales_data = []

ground_truth = {}

for region in regions:
    # 1. Generate Daily Spend (Random Walk + Noise)
    # Base daily spend varies by region
    base_spend = np.random.uniform(500, 2000)
    daily_spend = np.random.normal(base_spend, base_spend*0.3, len(dates))
    daily_spend = np.maximum(daily_spend, 100) # Floor at 100
    
    # Create DataFrame for this region
    df = pd.DataFrame({'date': dates, 'spend': daily_spend})
    df['month'] = df['date'].dt.to_period('M')
    
    # 2. Determine Sales Logic based on Region
    if region == 1: 
        # IMMEDIATE: Sales(t) = 5 * Spend(t) + Noise
        sales_mult = 5.0
        lag_days = 0
        df['sales'] = df['spend'] * sales_mult + np.random.normal(0, base_spend, len(dates))
    elif region == 2:
        # DELAYED: Sales(t) ~ Spend(t-30) 
        # To make it statistically clean for monthly aggregation:
        # We shift the spend signal by ~30 days for the sales generation
        sales_mult = 8.0
        lag_days = 30
        shifted_spend = np.roll(df['spend'], lag_days)
        shifted_spend[:lag_days] = base_spend # Fill start
        df['sales'] = shifted_spend * sales_mult + np.random.normal(0, base_spend, len(dates))
    elif region == 3:
        # INEFFECTIVE: Random sales
        sales_mult = 0.0
        df['sales'] = np.random.normal(5000, 1000, len(dates))
    elif region == 4:
        # STEADY/NOISE: High constant sales, constant spend
        df['spend'] = np.random.normal(1000, 50, len(dates))
        df['sales'] = np.random.normal(10000, 100, len(dates))
    else:
        # MIXED/WEAK IMMEDIATE
        df['sales'] = df['spend'] * 1.5 + np.random.normal(0, base_spend*2, len(dates))

    # Ensure non-negative
    df['sales'] = np.maximum(df['sales'], 0)
    
    # Add to list for DB insertion
    for _, row in df.iterrows():
        spend_data.append((row['date'], region, row['spend']))
        sales_data.append((row['date'], region, row['sales']))

    # 3. Calculate Ground Truth (Monthly Aggregation)
    monthly = df.groupby('month')[['spend', 'sales']].sum().reset_index()
    monthly['sales_next'] = monthly['sales'].shift(-1) # For Lag 1 (Spend M vs Sales M+1)
    
    # Filter for valid rows (drop last for lag calculation)
    valid_lag0 = monthly.dropna(subset=['spend', 'sales'])
    valid_lag1 = monthly.dropna(subset=['spend', 'sales_next'])
    
    # Lag 0 Stats
    corr0 = valid_lag0['spend'].corr(valid_lag0['sales'])
    slope0 = np.polyfit(valid_lag0['spend'], valid_lag0['sales'], 1)[0]
    
    # Lag 1 Stats
    corr1 = valid_lag1['spend'].corr(valid_lag1['sales_next'])
    slope1 = np.polyfit(valid_lag1['spend'], valid_lag1['sales_next'], 1)[0]
    
    # Strategy
    if corr0 < 0.3 and corr1 < 0.3:
        strat = 'INEFFECTIVE'
    elif corr1 > corr0:
        strat = 'DELAYED'
    else:
        strat = 'IMMEDIATE'
        
    ground_truth[str(region)] = {
        "corr0": float(corr0),
        "slope0": float(slope0),
        "corr1": float(corr1),
        "slope1": float(slope1),
        "strategy": strat,
        "total_spend": float(monthly['spend'].sum()),
        "total_sales": float(monthly['sales'].sum())
    }

# Save Ground Truth
with open('/var/lib/oracle/roi_ground_truth.json', 'w') as f:
    json.dump(ground_truth, f)

# Connect and Load Data
try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()
    
    print("Creating tables...")
    cursor.execute("""
        CREATE TABLE raw_ad_spend (
            spend_date DATE,
            region_id NUMBER,
            amount NUMBER(10, 2)
        )
    """)
    cursor.execute("""
        CREATE TABLE raw_sales (
            sale_date DATE,
            region_id NUMBER,
            amount NUMBER(10, 2)
        )
    """)
    
    print(f"Inserting {len(spend_data)} spend records...")
    cursor.executemany("INSERT INTO raw_ad_spend VALUES (:1, :2, :3)", spend_data)
    
    print(f"Inserting {len(sales_data)} sales records...")
    cursor.executemany("INSERT INTO raw_sales VALUES (:1, :2, :3)", sales_data)
    
    conn.commit()
    print("Data loaded successfully.")
    
except Exception as e:
    print(f"Database Error: {e}")
    exit(1)
PYEOF

# Set permissions for ground truth (hidden from ga)
chmod 600 /var/lib/oracle/roi_ground_truth.json
chown root:root /var/lib/oracle/roi_ground_truth.json

# Launch DBeaver (Agent Tool)
echo "Launching DBeaver..."
if ! pgrep -f dbeaver > /dev/null; then
    su - ga -c "DISPLAY=:1 /usr/local/bin/dbeaver &" > /dev/null 2>&1 || \
    su - ga -c "DISPLAY=:1 dbeaver &" > /dev/null 2>&1 || true
fi

# Initial Screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="