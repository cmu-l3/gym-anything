#!/bin/bash
echo "=== Setting up debug_geospatial_analysis task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="debug_geospatial_analysis"
PROJECT_DIR="/home/ga/PycharmProjects/city_mobility"

# 1. Clean previous state
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/${TASK_NAME}_result.json /tmp/${TASK_NAME}_start_ts 2>/dev/null || true

# 2. Create Directory Structure
su - ga -c "mkdir -p $PROJECT_DIR/mobility $PROJECT_DIR/tests $PROJECT_DIR/data"

# 3. Create Requirements
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
pandas>=2.0.0
numpy>=1.24.0
pytest>=7.0
EOF

# 4. Create Data (Shuffled CSV to trigger sorting bug)
cat > "$PROJECT_DIR/data/sample_trace.csv" << 'EOF'
vehicle_id,timestamp,latitude,longitude
V001,2024-03-10 08:00:00,40.712800,-74.006000
V001,2024-03-10 08:00:10,40.712850,-74.006000
V001,2024-03-10 08:00:30,40.712950,-74.006000
V001,2024-03-10 08:00:20,40.712900,-74.006000
V002,2024-03-10 08:05:00,40.758000,-73.985500
V002,2024-03-10 08:05:05,40.758100,-73.985500
EOF
# Note: Line 4 (08:00:20) is out of order vs Line 3 (08:00:30)

# 5. Create Source Code (Buggy)

# mobility/__init__.py
touch "$PROJECT_DIR/mobility/__init__.py"

# mobility/geo.py (Bug 1: Missing radians conversion)
cat > "$PROJECT_DIR/mobility/geo.py" << 'EOF'
"""Geodetic calculations."""
import math

EARTH_RADIUS_M = 6371000

def haversine_distance(lat1, lon1, lat2, lon2):
    """
    Calculate the great circle distance between two points 
    on the earth (specified in decimal degrees).
    Returns distance in meters.
    """
    # BUG: Haversine formula requires radians, but inputs are used directly in degrees
    dlat = lat2 - lat1
    dlon = lon2 - lon1

    a = math.sin(dlat / 2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

    return EARTH_RADIUS_M * c
EOF

# mobility/processing.py (Bug 2: Missing sort)
cat > "$PROJECT_DIR/mobility/processing.py" << 'EOF'
"""Data processing pipeline."""
import pandas as pd
from .geo import haversine_distance

def calculate_deltas(df: pd.DataFrame) -> pd.DataFrame:
    """
    Calculate time deltas (seconds) and distance deltas (meters) 
    between consecutive GPS points for each vehicle.
    """
    df = df.copy()
    
    # Ensure timestamp is datetime
    df['timestamp'] = pd.to_datetime(df['timestamp'])
    
    # BUG: Data is not sorted by time before calculating diff().
    # If the CSV is out of order, this calculates distance between non-consecutive points.
    # Should be: df = df.sort_values(by=['vehicle_id', 'timestamp'])
    
    # Group by vehicle to avoid calculating delta between different cars
    grouped = df.groupby('vehicle_id')
    
    df['prev_lat'] = grouped['latitude'].shift(1)
    df['prev_lon'] = grouped['longitude'].shift(1)
    df['prev_ts'] = grouped['timestamp'].shift(1)
    
    # Calculate time delta in seconds
    df['time_delta_s'] = (df['timestamp'] - df['prev_ts']).dt.total_seconds()
    
    # Calculate distance delta using vectorized map (apply is slow but clear for this demo)
    # We use a lambda to call our custom haversine function
    df['dist_delta_m'] = df.apply(
        lambda row: haversine_distance(
            row['prev_lat'], row['prev_lon'], 
            row['latitude'], row['longitude']
        ) if pd.notnull(row['prev_lat']) else 0.0,
        axis=1
    )
    
    return df
EOF

# mobility/metrics.py (Bug 3: Units, Bug 4: Filter)
cat > "$PROJECT_DIR/mobility/metrics.py" << 'EOF'
"""Traffic metrics calculations."""
import pandas as pd

def calculate_speed(df: pd.DataFrame) -> pd.DataFrame:
    """
    Calculate speed in km/h from distance (m) and time (s).
    """
    df = df.copy()
    
    # Avoid division by zero
    mask = df['time_delta_s'] > 0
    
    # BUG: Calculation results in m/s (meters / seconds), but column is named speed_kph.
    # Should multiply by 3.6 to convert m/s to km/h.
    df.loc[mask, 'speed_kph'] = df.loc[mask, 'dist_delta_m'] / df.loc[mask, 'time_delta_s']
    
    return df

def identify_congestion(df: pd.DataFrame) -> pd.DataFrame:
    """
    Filter data to identify congestion points (low speed) 
    and remove GPS noise (impossible high speeds).
    """
    # BUG: Logic is inverted or wrong.
    # We want to keep valid data (e.g. < 150 km/h) and identify congestion (< 10 km/h).
    # The current filter removes everything > 5. Wait, the goal of this function in the pipeline
    # is often to clean data first.
    # The prompt says: "Congestion report comes back empty".
    # And "currently filters valid low speeds instead of invalid high speeds".
    
    # Current implementation:
    # df['speed_kph'] > 5 keeps moving cars. It DROPS the traffic jam (0-5 kph).
    # It also keeps the supersonic noise (10000 kph).
    
    clean_df = df[df['speed_kph'] > 5].copy()
    
    return clean_df
EOF

# 6. Create Tests

# tests/conftest.py
cat > "$PROJECT_DIR/tests/conftest.py" << 'EOF'
import pytest
import pandas as pd

@pytest.fixture
def unsorted_trace():
    data = {
        'vehicle_id': ['V1', 'V1', 'V1'],
        'timestamp': [
            '2024-01-01 10:00:00',
            '2024-01-01 10:00:20', # Out of order
            '2024-01-01 10:00:10'
        ],
        'latitude': [0.0, 0.002, 0.001], # ~111m per 0.001 deg
        'longitude': [0.0, 0.0, 0.0]
    }
    return pd.DataFrame(data)
EOF

# tests/test_geo.py
cat > "$PROJECT_DIR/tests/test_geo.py" << 'EOF'
import pytest
from mobility.geo import haversine_distance
import math

def test_haversine_zero_distance():
    assert haversine_distance(0, 0, 0, 0) == 0.0

def test_haversine_known_distance():
    # Distance between (0,0) and (0,1) degrees equator is ~111,319 meters
    # The buggy version (using degrees as radians) returns ~139 meters or garbage
    dist = haversine_distance(0, 0, 0, 1)
    assert 111000 < dist < 112000, f"Expected ~111km, got {dist} meters"

def test_haversine_poles():
    # Distance from pole to pole is ~20,000 km
    dist = haversine_distance(90, 0, -90, 0)
    assert 19000000 < dist < 21000000

def test_haversine_radians_fix():
    # Specific check that radians conversion is likely happening
    # 90 degrees = pi/2 radians. sin(90) = 0.89 (deg) vs 1.0 (rad)
    # This test fails if degrees are passed to trig functions
    dist = haversine_distance(0, 0, 1, 0) # 1 deg lat ~ 111km
    assert dist > 100000
EOF

# tests/test_processing.py
cat > "$PROJECT_DIR/tests/test_processing.py" << 'EOF'
import pytest
import pandas as pd
from mobility.processing import calculate_deltas

def test_calculate_deltas_sorting(unsorted_trace):
    # Input has t0, t2, t1 order. 
    # If not sorted, deltas will be t0->t2 (20s) and t2->t1 (-10s)
    # If sorted, deltas will be t0->t1 (10s) and t1->t2 (10s)
    
    df = calculate_deltas(unsorted_trace)
    
    # Check that time deltas are positive (implies chronological order)
    # The first point for a vehicle has NaN delta, subsequent should be > 0
    deltas = df['time_delta_s'].dropna()
    assert (deltas > 0).all(), "Found negative or zero time deltas, implying unsorted data"
    
    # Check specific values
    assert (deltas == 10.0).all()

def test_calculate_deltas_columns(unsorted_trace):
    df = calculate_deltas(unsorted_trace)
    assert 'dist_delta_m' in df.columns
    assert 'time_delta_s' in df.columns

def test_calculate_deltas_grouping():
    data = {
        'vehicle_id': ['A', 'B'],
        'timestamp': ['2024-01-01 10:00', '2024-01-01 10:00'],
        'latitude': [0, 10],
        'longitude': [0, 10]
    }
    df = pd.DataFrame(data)
    res = calculate_deltas(df)
    # Should be NaNs because no previous point for either vehicle
    assert res['dist_delta_m'].isna().all()
EOF

# tests/test_metrics.py
cat > "$PROJECT_DIR/tests/test_metrics.py" << 'EOF'
import pytest
import pandas as pd
from mobility.metrics import calculate_speed, identify_congestion

def test_calculate_speed_units():
    # 1000 meters in 3600 seconds = 1 km in 1 hour = 1 km/h
    # Buggy version gives 1000/3600 = 0.277 km/h (which is actually m/s)
    df = pd.DataFrame({
        'dist_delta_m': [1000],
        'time_delta_s': [3600]
    })
    df = calculate_speed(df)
    speed = df['speed_kph'].iloc[0]
    assert speed == pytest.approx(1.0, 0.01), f"Expected 1.0 km/h, got {speed}"

def test_calculate_speed_zero_time():
    df = pd.DataFrame({
        'dist_delta_m': [100],
        'time_delta_s': [0]
    })
    df = calculate_speed(df)
    # Should not crash or produce inf in a way that breaks pipeline (NaN is acceptable or handled)
    # Our implementation leaves it as NaN or unassigned if we filter by mask
    if 'speed_kph' in df.columns:
        assert pd.isna(df['speed_kph'].iloc[0]) or df['speed_kph'].iloc[0] == 0

def test_identify_congestion_keeps_traffic_jam():
    # Traffic jam: speed is 2 km/h. Should BE KEPT (or identified).
    # The buggy filter removed everything <= 5.
    df = pd.DataFrame({'speed_kph': [2.0, 4.0]})
    clean = identify_congestion(df)
    assert len(clean) == 2, "Congestion (low speed) data was incorrectly filtered out"

def test_identify_congestion_removes_noise():
    # GPS noise: 500 km/h. Should be REMOVED.
    df = pd.DataFrame({'speed_kph': [50.0, 500.0]})
    clean = identify_congestion(df)
    assert len(clean) == 1
    assert clean.iloc[0]['speed_kph'] == 50.0
EOF

# 7. Record Start Time
date +%s > /tmp/${TASK_NAME}_start_ts

# 8. Open PyCharm
echo "Launching PyCharm..."
source /workspace/scripts/task_utils.sh
setup_pycharm_project "$PROJECT_DIR" "city_mobility"

echo "=== Setup complete ==="