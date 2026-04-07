#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fix Smart Meter Data Pipeline Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

WORKSPACE_DIR="/home/ga/workspace/smart_meter_pipeline"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"
cd "$WORKSPACE_DIR"

# ─────────────────────────────────────────────────────────────
# 1. Generate realistic synthetic UCI-style smart meter data
# ─────────────────────────────────────────────────────────────
echo "Generating smart meter telemetry data..."

python3 << 'PYDATA' > "$WORKSPACE_DIR/data/meter_readings.csv"
import csv
from datetime import datetime, timedelta
import random
import math

start_date = datetime(2007, 1, 1, 0, 0)
print("Date;Time;Global_active_power")

for i in range(60 * 24 * 60):  # 60 days of minute-level data
    current = start_date + timedelta(minutes=i)
    # European date format DD/MM/YYYY
    date_str = current.strftime("%d/%m/%Y")
    time_str = current.strftime("%H:%M:%S")
    
    # Base load + daily pattern + seasonal drift (winter heating)
    hour = current.hour
    daily = 1.0 + math.sin((hour - 6) * math.pi / 12) * 1.5
    seasonal = (i / (60 * 24 * 60)) * 2.0 
    
    power = max(0.2, daily + seasonal + random.uniform(-0.5, 0.5))
    
    # Inject missing data ('?')
    if random.random() < 0.005:
        power_str = "?"
    else:
        power_str = f"{power:.3f}"
        
    print(f"{date_str};{time_str};{power_str}")
PYDATA

echo "Generated 60 days of minute-level telemetry data."

# ─────────────────────────────────────────────────────────────
# 2. pipeline files with specific bugs
# ─────────────────────────────────────────────────────────────

cat > "$WORKSPACE_DIR/data_loader.py" << 'EOF'
import pandas as pd

def load_data(filepath):
    """Loads raw telemetry data."""
    df = pd.read_csv(filepath, sep=';', low_memory=False)
    df['datetime'] = df['Date'] + ' ' + df['Time']
    
    # BUG 1: pd.to_datetime without dayfirst=True or format assumes US dates (MM/DD/YYYY)
    # This causes 01/02/2007 to be parsed as January 2nd instead of February 1st!
    df['datetime'] = pd.to_datetime(df['datetime'])
    
    df.set_index('datetime', inplace=True)
    df.sort_index(inplace=True)
    return df
EOF

cat > "$WORKSPACE_DIR/cleaner.py" << 'EOF'
import pandas as pd
import numpy as np

def clean_data(df):
    """Cleans the raw telemetry data."""
    # Replace the string missing value indicator with NaN
    df = df.replace('?', np.nan)
    df['Global_active_power'] = pd.to_numeric(df['Global_active_power'])
    
    # BUG 2: Filling missing power readings with 0.0 creates artificial sudden drops.
    # We should use .interpolate() or .ffill() for physical time-series sensors.
    df['Global_active_power'] = df['Global_active_power'].fillna(0.0)
    
    return df
EOF

cat > "$WORKSPACE_DIR/aggregator.py" << 'EOF'
import pandas as pd

def aggregate_hourly_energy(df):
    """Aggregates minute-level power readings into hourly energy consumption."""
    # Global_active_power is in kilowatts (kW), measured every minute.
    
    # BUG 3: Summing kW over 60 minutes yields 60x the actual kWh energy!
    # If a heater draws 2 kW steadily for an hour, the energy used is 2 kWh.
    # Summing sixty 2 kW readings gives 120... Needs to be .mean() or summed and divided by 60.
    hourly = df[['Global_active_power']].resample('H').sum()
    
    hourly.rename(columns={'Global_active_power': 'energy_kwh'}, inplace=True)
    return hourly
EOF

cat > "$WORKSPACE_DIR/tariff_calculator.py" << 'EOF'
import pandas as pd

def apply_tariffs(df):
    """Applies Time-of-Use (TOU) tariffs to calculate cost."""
    # Peak pricing applies from 17:00 to 20:00 (5 PM to 8 PM)
    
    # BUG 4: <= 20 includes the entire 20:00 to 20:59 hour.
    # Peak should end precisely at 20:00. This overcharges customers by 1 hour every day.
    df['is_peak'] = (df.index.hour >= 17) & (df.index.hour <= 20)
    
    # Apply rates: $0.35/kWh peak, $0.12/kWh off-peak
    df['cost'] = df['energy_kwh'] * df['is_peak'].map({True: 0.35, False: 0.12})
    return df
EOF

cat > "$WORKSPACE_DIR/anomaly_detector.py" << 'EOF'
import pandas as pd

def detect_anomalies(df):
    """Flags anomalous high energy consumption."""
    # BUG 5: Uses all-time mean and std, ignoring seasonal drift (e.g. winter heating).
    # This flags normal late-winter usage as anomalous. Needs a rolling window (e.g. 30 days).
    mean = df['energy_kwh'].mean()
    std = df['energy_kwh'].std()
    
    df['z_score'] = (df['energy_kwh'] - mean) / std
    df['is_anomaly'] = df['z_score'] > 3.0
    
    return df
EOF

cat > "$WORKSPACE_DIR/pipeline.py" << 'EOF'
from data_loader import load_data
from cleaner import clean_data
from aggregator import aggregate_hourly_energy
from tariff_calculator import apply_tariffs
from anomaly_detector import detect_anomalies

def run_pipeline(filepath):
    print("Loading data...")
    df = load_data(filepath)
    print("Cleaning data...")
    df = clean_data(df)
    print("Aggregating energy...")
    hourly = aggregate_hourly_energy(df)
    print("Applying tariffs...")
    billed = apply_tariffs(hourly)
    print("Detecting anomalies...")
    results = detect_anomalies(billed)
    
    anomalies = results[results['is_anomaly']]
    print(f"Pipeline complete. Found {len(anomalies)} anomalies.")
    return results

if __name__ == "__main__":
    run_pipeline("data/meter_readings.csv")
EOF

# ─────────────────────────────────────────────────────────────
# 3. Test suite
# ─────────────────────────────────────────────────────────────

cat > "$WORKSPACE_DIR/tests/test_pipeline.py" << 'EOF'
import pandas as pd
import pytest
from data_loader import load_data
from cleaner import clean_data
from aggregator import aggregate_hourly_energy
from tariff_calculator import apply_tariffs
from anomaly_detector import detect_anomalies

def test_data_loader():
    df = load_data('data/meter_readings.csv')
    # If 01/02/2007 is parsed as Jan 2, the index won't be strictly monotonic 
    # when it encounters real Jan dates after it.
    assert df.index.is_monotonic_increasing, "Index is not monotonic. Date parsing is likely confusing European format (DD/MM/YYYY) for US format."

def test_cleaner():
    df = load_data('data/meter_readings.csv')
    df = clean_data(df)
    # Check that we didn't fill missing with 0.0 inappropriately
    assert not (df['Global_active_power'] == 0.0).any(), "Found 0.0 values in power. Missing sensor data should be interpolated or forward-filled, not zeroed."

def test_aggregator():
    df = load_data('data/meter_readings.csv')
    df = clean_data(df)
    hourly = aggregate_hourly_energy(df)
    # Normal residential hourly energy is generally < 15 kWh
    assert hourly['energy_kwh'].max() < 15.0, "Energy values are unreasonably high. Did you sum kW directly without converting to kWh?"

def test_tariff_calculator():
    df = load_data('data/meter_readings.csv')
    df = clean_data(df)
    hourly = aggregate_hourly_energy(df)
    with_tariffs = apply_tariffs(hourly)
    # 20:00 hour should NOT be peak (peak is 17:00 to 19:59)
    peaks = with_tariffs[with_tariffs['is_peak']]
    assert 20 not in peaks.index.hour.unique(), "Hour 20 (8 PM - 9 PM) is incorrectly marked as peak."

def test_anomaly_detector():
    df = load_data('data/meter_readings.csv')
    df = clean_data(df)
    hourly = aggregate_hourly_energy(df)
    anomalies = detect_anomalies(hourly)
    # Ensure there isn't a massive block of anomalies (e.g. whole winter)
    anomaly_pct = anomalies['is_anomaly'].mean()
    assert anomaly_pct < 0.05, "Too many anomalies detected. The baseline is drifting seasonally, requiring a rolling window instead of a global mean/std."
EOF

# Ensure ga user owns the workspace
chown -R ga:ga "$WORKSPACE_DIR"

# Ensure pytest is installed
sudo -u ga pip install --no-cache-dir pytest pandas numpy > /dev/null 2>&1 || true

# Open the workspace in VS Code
echo "Opening VS Code..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' &"

# Wait for VS Code to load and maximize
sleep 5
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true

echo "=== Setup complete ==="