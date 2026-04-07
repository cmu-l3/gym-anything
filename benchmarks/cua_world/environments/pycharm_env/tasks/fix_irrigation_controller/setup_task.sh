#!/bin/bash
echo "=== Setting up fix_irrigation_controller task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="fix_irrigation_controller"
PROJECT_DIR="/home/ga/PycharmProjects/smart_irrigate"

# Clean previous runs
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/${TASK_NAME}_result.json /tmp/${TASK_NAME}_start_ts 2>/dev/null || true

# Record start time
date +%s > /tmp/${TASK_NAME}_start_ts

# Create project structure
mkdir -p "$PROJECT_DIR/control"
mkdir -p "$PROJECT_DIR/data"
mkdir -p "$PROJECT_DIR/tests"

# --- Requirements ---
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
pytest>=7.0
numpy>=1.24.0
EOF

# --- control/__init__.py ---
touch "$PROJECT_DIR/control/__init__.py"

# --- control/evapotranspiration.py (BUG 1) ---
# Hargreaves Equation: 0.0023 * Ra * (Tmean + 17.8) * sqrt(Tmax - Tmin)
# Bug: Uses (Tmean - 17.8)
cat > "$PROJECT_DIR/control/evapotranspiration.py" << 'EOF'
"""
Evapotranspiration (ETo) calculation modules.
Implements standard agricultural formulas for reference crop water usage.
"""
import math


def calculate_eto_hargreaves(t_min: float, t_max: float, t_mean: float, ra: float) -> float:
    """
    Calculate Reference Evapotranspiration (ETo) using the Hargreaves-Samani equation.
    
    Args:
        t_min (float): Minimum daily temperature (Celsius)
        t_max (float): Maximum daily temperature (Celsius)
        t_mean (float): Mean daily temperature (Celsius)
        ra (float): Extraterrestrial radiation (MJ m-2 day-1)
        
    Returns:
        float: ETo in mm/day
    """
    # Validation
    if t_max < t_min:
        raise ValueError("Tmax cannot be less than Tmin")
    
    # Hargreaves Coefficient
    hc = 0.0023
    
    # BUG: The formula constant is +17.8, not -17.8
    # This causes significant under-estimation of water needs
    eto = hc * ra * (t_mean - 17.8) * math.sqrt(t_max - t_min)
    
    return max(0.0, eto)
EOF

# --- control/scheduler.py (BUG 2) ---
# Logic: Should return False (don't water) if rain_prob > threshold
# Bug: Returns False if rain_prob < threshold (don't water if it's dry?!)
cat > "$PROJECT_DIR/control/scheduler.py" << 'EOF'
"""
Irrigation scheduling logic based on weather forecasts.
"""

def should_water(soil_moisture: float, rain_probability: float, moisture_threshold: float = 30.0, rain_threshold: float = 0.6) -> bool:
    """
    Determine if irrigation should turn on for the day.
    
    Args:
        soil_moisture (float): Current VWC (Volumetric Water Content) % (0-100)
        rain_probability (float): Forecast probability of precipitation (0.0-1.0)
        moisture_threshold (float): Soil moisture level below which watering is needed
        rain_threshold (float): Probability above which we skip watering to save water
        
    Returns:
        bool: True if valves should open, False otherwise
    """
    # Safety check
    if not (0 <= soil_moisture <= 100):
        raise ValueError("Invalid soil moisture percentage")
    
    # BUG: Logic inversion.
    # We want to SKIP watering if rain is LIKELY (> threshold).
    # Current code skips watering if rain is UNLIKELY (< threshold),
    # meaning it waters during storms and skips during droughts.
    if rain_probability < rain_threshold:
        return False
        
    # Check soil moisture
    if soil_moisture < moisture_threshold:
        return True
        
    return False
EOF

# --- control/sensors.py (BUG 3) ---
# Crash on None in list
cat > "$PROJECT_DIR/control/sensors.py" << 'EOF'
"""
Sensor data processing and aggregation.
Handles reading inputs from distributed IoT nodes.
"""
from typing import List, Optional

def aggregate_readings(readings: List[Optional[float]]) -> float:
    """
    Compute the average value from a list of sensor readings.
    Handles network dropouts where readings might be None.
    
    Args:
        readings: List of float values or None (if packet lost)
        
    Returns:
        float: Average of valid readings. Returns 0.0 if no valid readings.
    """
    if not readings:
        return 0.0
        
    # BUG: sum() throws TypeError if list contains None.
    # Need to filter None values first.
    total = sum(readings)
    count = len(readings)
    
    if count == 0:
        return 0.0
        
    return total / count
EOF

# --- tests/conftest.py ---
cat > "$PROJECT_DIR/tests/conftest.py" << 'EOF'
import pytest
EOF

# --- tests/test_eto.py ---
cat > "$PROJECT_DIR/tests/test_eto.py" << 'EOF'
import pytest
import math
from control.evapotranspiration import calculate_eto_hargreaves

def test_hargreaves_basic():
    # Example values: Tmin=10, Tmax=30, Tmean=20, Ra=15
    # Correct: 0.0023 * 15 * (20 + 17.8) * sqrt(30-10)
    #        = 0.0345 * 37.8 * 4.472
    #        = 5.83 mm/day
    
    # Buggy version (20 - 17.8) gives ~0.34 mm/day (Huge error)
    
    eto = calculate_eto_hargreaves(10, 30, 20, 15)
    assert math.isclose(eto, 5.83, rel_tol=0.01)

def test_hargreaves_zero_radiation():
    assert calculate_eto_hargreaves(10, 20, 15, 0) == 0.0

def test_hargreaves_invalid_temps():
    with pytest.raises(ValueError):
        calculate_eto_hargreaves(30, 10, 20, 15)

def test_hargreaves_high_heat():
    # Tmean=35, Tmax=45, Tmin=25, Ra=18
    # 0.0023 * 18 * (35 + 17.8) * sqrt(20)
    # 0.0414 * 52.8 * 4.472 = 9.77
    eto = calculate_eto_hargreaves(25, 45, 35, 18)
    assert math.isclose(eto, 9.77, rel_tol=0.01)
EOF

# --- tests/test_scheduler.py ---
cat > "$PROJECT_DIR/tests/test_scheduler.py" << 'EOF'
import pytest
from control.scheduler import should_water

def test_should_water_dry_soil_no_rain():
    # Soil is dry (20 < 30), Rain is unlikely (0.1 < 0.6) -> Should Water
    assert should_water(20.0, 0.1) is True

def test_skip_watering_if_rain_likely():
    # Soil is dry (20 < 30), BUT Rain is likely (0.9 > 0.6) -> Should SKIP
    assert should_water(20.0, 0.9) is False

def test_no_water_if_soil_wet():
    # Soil is wet (80 > 30), No rain (0.1) -> No Water needed
    assert should_water(80.0, 0.1) is False

def test_invalid_inputs():
    with pytest.raises(ValueError):
        should_water(150.0, 0.1)
EOF

# --- tests/test_sensors.py ---
cat > "$PROJECT_DIR/tests/test_sensors.py" << 'EOF'
import pytest
from control.sensors import aggregate_readings

def test_average_clean_data():
    data = [10.0, 20.0, 30.0]
    assert aggregate_readings(data) == 20.0

def test_average_with_dropped_packets():
    # This fails in buggy version (TypeError)
    data = [10.0, None, 30.0, None, 20.0]
    # Valid: 10, 30, 20 -> avg 20
    assert aggregate_readings(data) == 20.0

def test_all_none():
    data = [None, None]
    assert aggregate_readings(data) == 0.0

def test_empty_list():
    assert aggregate_readings([]) == 0.0
EOF

# --- Setup Environment ---
echo "Setting permissions..."
chown -R ga:ga "$PROJECT_DIR"

# Launch PyCharm
echo "Launching PyCharm..."
setup_pycharm_project "$PROJECT_DIR" "smart_irrigate" 120

# Take screenshot
take_screenshot /tmp/fix_irrigation_initial.png

echo "=== Setup complete ==="