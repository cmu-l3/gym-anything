#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Repair Epidemiological Data Pipeline Task ==="

WORKSPACE_DIR="/home/ga/workspace/surveillance_pipeline"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data"
sudo -u ga mkdir -p "$WORKSPACE_DIR/pipeline"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"
sudo -u ga mkdir -p "$WORKSPACE_DIR/output"

cd "$WORKSPACE_DIR"

# ──────────────────────────────────────────────────────────
# 1. Generate Raw Surveillance Data
# ──────────────────────────────────────────────────────────
echo "Generating surveillance data..."

sudo -u ga python3 << 'PYDATA' > "$WORKSPACE_DIR/data/raw_surveillance_data.csv"
import csv
from datetime import datetime, timedelta
import random

random.seed(42)

regions = {
    "North": {"population": 1500000},
    "South": {"population": 2200000}
}

writer = csv.writer(sys.stdout)
writer.writerow(["date", "region", "cumulative_cases", "hospitalizations", "population"])

start_date = datetime(2020, 1, 1)

for region, data in regions.items():
    cumulative = 0
    for day in range(150): # Jan 1 to May 29
        current_date = start_date + timedelta(days=day)
        
        # Incident cases (simulating a wave)
        if day < 30:
            incident = random.randint(0, 5)
        elif day < 90:
            incident = int(random.gauss(50, 15))
        else:
            incident = int(random.gauss(10, 5))
            
        incident = max(0, incident)
        cumulative += incident
        
        # Hospitalizations (missing in early reporting, start in March)
        if current_date.month < 3:
            hosp = ""
        else:
            hosp = int(incident * 0.1)
            
        # Format date as DD/MM/YYYY (European standard causing parsing bugs in US locale)
        date_str = current_date.strftime("%d/%m/%Y")
        
        writer.writerow([date_str, region, cumulative, hosp, data["population"]])
PYDATA

# ──────────────────────────────────────────────────────────
# 2. pipeline/data_loader.py (BUGS: naive datetime parse + overzealous dropna)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/pipeline/data_loader.py" << 'EOF'
"""Data loading and cleaning module."""
import pandas as pd

def load_and_clean_data(filepath: str) -> pd.DataFrame:
    """Load raw surveillance data and prepare for analysis."""
    df = pd.read_csv(filepath)
    
    # Parse dates
    # BUG 1: pd.to_datetime interprets DD/MM/YYYY as MM/DD/YYYY where possible (e.g. 05/01/2020 becomes May 1)
    df['date'] = pd.to_datetime(df['date'])
    
    # Handle missing values
    # BUG 2: This drops all rows before March because 'hospitalizations' is NaN, destroying early case data
    df = df.dropna()
    
    # Sort for safety
    df = df.sort_values(by=['region', 'date'])
    
    return df
EOF

# ──────────────────────────────────────────────────────────
# 3. pipeline/metrics.py (BUGS: global diff, wrong multiplier, unsorted rolling)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/pipeline/metrics.py" << 'EOF'
"""Epidemiological metrics calculation module."""
import pandas as pd

def calculate_daily_incident_cases(df: pd.DataFrame) -> pd.DataFrame:
    """Convert cumulative case counts to daily incident cases."""
    # BUG 3: .diff() applied globally across regions creates massive negative/positive spikes at region boundaries
    df['daily_cases'] = df['cumulative_cases'].diff().fillna(df['cumulative_cases'])
    
    # Clean up any potential negatives
    df.loc[df['daily_cases'] < 0, 'daily_cases'] = 0
    
    return df

def calculate_population_rates(df: pd.DataFrame) -> pd.DataFrame:
    """Calculate cases per 100,000 population."""
    # BUG 4: Multiplying by 1,000 instead of 100,000
    df['cases_per_100k'] = (df['daily_cases'] / df['population']) * 1000
    return df

def calculate_rolling_averages(df: pd.DataFrame, window: int = 7) -> pd.DataFrame:
    """Calculate 7-day rolling average of daily cases."""
    # BUG 5: Rolling average applied without ensuring chronological sorting first
    # Data might be out of order due to previous operations, causing chaotic rolling averages
    df['rolling_avg_7d'] = df.groupby('region')['daily_cases'].transform(
        lambda x: x.rolling(window, min_periods=1).mean()
    )
    return df
EOF

# ──────────────────────────────────────────────────────────
# 4. run_pipeline.py
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/run_pipeline.py" << 'EOF'
"""Main pipeline execution script."""
import os
from pipeline.data_loader import load_and_clean_data
from pipeline.metrics import (
    calculate_daily_incident_cases,
    calculate_population_rates,
    calculate_rolling_averages
)

def main():
    print("Starting Epidemiological Data Pipeline...")
    
    # Load and clean
    df = load_and_clean_data("data/raw_surveillance_data.csv")
    print(f"Loaded {len(df)} records.")
    
    # Calculate metrics
    df = calculate_daily_incident_cases(df)
    df = calculate_population_rates(df)
    df = calculate_rolling_averages(df)
    
    # Export
    output_path = "output/processed_surveillance_data.csv"
    df.to_csv(output_path, index=False)
    print(f"Pipeline complete. Data exported to {output_path}")

if __name__ == "__main__":
    main()
EOF

# ──────────────────────────────────────────────────────────
# 5. tests/test_pipeline.py
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/tests/test_pipeline.py" << 'EOF'
import pandas as pd
import pytest
from pipeline.data_loader import load_and_clean_data
from pipeline.metrics import (
    calculate_daily_incident_cases,
    calculate_population_rates,
    calculate_rolling_averages
)

@pytest.fixture
def raw_data_path():
    return "data/raw_surveillance_data.csv"

def test_date_parsing_correctness(raw_data_path):
    """Test that dates like 02/01/2020 (Jan 2nd) are parsed correctly, not as Feb 1st."""
    df = load_and_clean_data(raw_data_path)
    # January data should exist
    jan_data = df[df['date'].dt.month == 1]
    assert len(jan_data) > 0, "January data is missing! Dates may be parsed incorrectly (MM/DD/YYYY instead of DD/MM/YYYY)."

def test_missing_data_retention(raw_data_path):
    """Test that early data is not dropped just because hospitalizations are missing."""
    df = load_and_clean_data(raw_data_path)
    # We generated 150 days of data per region (300 rows total)
    assert len(df) > 200, "Too many rows dropped! Early case data must be retained even if hospitalizations are NaN."

def test_daily_incident_conversion():
    """Test that cumulative to incident conversion doesn't bleed across regions."""
    # Fake dataset with two regions
    df = pd.DataFrame({
        'region': ['North', 'North', 'South', 'South'],
        'cumulative_cases': [10, 20, 5, 15]
    })
    result = calculate_daily_incident_cases(df)
    
    # South's first incident case should be 5, not (5 - 20)
    south_first_day = result[(result['region'] == 'South')]['daily_cases'].iloc[0]
    assert south_first_day == 5, f"Daily cases bled across regions! Expected 5, got {south_first_day}"

def test_population_rate_calculation():
    """Test cases per 100k scaling."""
    df = pd.DataFrame({
        'daily_cases': [50],
        'population': [100000]
    })
    result = calculate_population_rates(df)
    # 50 cases in 100k population = 50 per 100k
    assert result['cases_per_100k'].iloc[0] == 50, "Rate calculation is mathematically incorrect! Check your multiplier."

def test_rolling_average_sorting():
    """Test that rolling average is calculated chronologically, ignoring current dataframe order."""
    df = pd.DataFrame({
        'region': ['North', 'North', 'North'],
        'date': pd.to_datetime(['2020-01-03', '2020-01-01', '2020-01-02']),
        'daily_cases': [30, 10, 20]
    })
    # If it rolls on current order (30, 10, 20), a 2-day roll gives [NaN, 20, 15]
    # If sorted (10, 20, 30), a 2-day roll gives [NaN, 15, 25]
    result = calculate_rolling_averages(df, window=2)
    
    # Get the value for Jan 3rd
    jan3_val = result[result['date'] == '2020-01-03']['rolling_avg_7d'].iloc[0]
    assert jan3_val == 25, "Rolling average is calculating out of chronological order! Ensure data is sorted by date."
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Ensure pytest is installed
pip3 install pytest pandas > /dev/null 2>&1

# Record task start time
date +%s > /tmp/task_start_time.txt

# Start VSCode
echo "Starting VSCode..."
su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR" &

# Wait for VSCode window
wait_for_window "Visual Studio Code" 30
sleep 5

# Maximize VSCode
focus_vscode_window 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="