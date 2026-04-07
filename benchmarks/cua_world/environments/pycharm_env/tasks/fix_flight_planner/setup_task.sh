#!/bin/bash
set -e
echo "=== Setting up fix_flight_planner task ==="

# Load shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/PycharmProjects/flight_planner"

# 1. Clean previous state
rm -rf "$PROJECT_DIR"
rm -f /tmp/flight_planner_result.json /tmp/flight_planner_start_ts

# 2. Create directory structure
mkdir -p "$PROJECT_DIR/planner"
mkdir -p "$PROJECT_DIR/tests"
mkdir -p "$PROJECT_DIR/data"

# 3. Create Data File (Airports)
cat > "$PROJECT_DIR/data/airports.csv" << 'CSVEOF'
ident,name,latitude_deg,longitude_deg,elevation_ft
KJFK,John F Kennedy International Airport,40.6413,-73.7781,13
EGLL,London Heathrow Airport,51.4700,-0.4543,83
KLAX,Los Angeles International Airport,33.9416,-118.4085,125
RJTT,Tokyo Haneda International Airport,35.5494,139.7798,21
YSSY,Sydney Kingsford Smith International Airport,-33.9399,151.1753,21
CSVEOF

# 4. Create Source Code with BUGS

# geo.py - Bugs: Returns KM instead of NM; Uses atan instead of atan2
cat > "$PROJECT_DIR/planner/geo.py" << 'PYEOF'
import math

def calculate_distance(lat1, lon1, lat2, lon2):
    """
    Calculate Great Circle distance between two points in Nautical Miles (NM).
    Uses Haversine formula.
    """
    # Convert decimal degrees to radians
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)

    a = math.sin(dphi / 2)**2 + \
        math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

    # BUG: Uses Earth radius in KM (6371), but docstring promises NM.
    # 1 NM = 1.852 km. Radius in NM is approx 3440.
    R = 6371.0 
    
    distance = R * c
    return distance

def calculate_bearing(lat1, lon1, lat2, lon2):
    """
    Calculate initial bearing (forward azimuth) from point A to B.
    Returns degrees (0-360).
    """
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    lambda1 = math.radians(lon1)
    lambda2 = math.radians(lon2)

    y = math.sin(lambda2 - lambda1) * math.cos(phi2)
    x = math.cos(phi1) * math.sin(phi2) - \
        math.sin(phi1) * math.cos(phi2) * math.cos(lambda2 - lambda1)

    # BUG: Uses atan which has quadrant ambiguity (-90 to 90)
    # Should use atan2(y, x) to get full -180 to 180 range correctly
    bearing_rad = math.atan(y / x) if x != 0 else 0
    
    bearing_deg = math.degrees(bearing_rad)
    return (bearing_deg + 360) % 360
PYEOF

# wind.py - Bug: Adds headwind instead of subtracting
cat > "$PROJECT_DIR/planner/wind.py" << 'PYEOF'
import math

def calculate_ground_speed(true_airspeed, course_deg, wind_speed, wind_dir_deg):
    """
    Calculate effective ground speed (GS) given:
    - true_airspeed (TAS) in knots
    - course_deg: Intended track (0-360)
    - wind_speed: Wind speed in knots
    - wind_dir_deg: Wind direction (FROM) in degrees
    """
    # Convert to radians
    wind_rad = math.radians(wind_dir_deg)
    course_rad = math.radians(course_deg)
    
    # Calculate angle between wind and course
    relative_angle = wind_rad - course_rad
    
    # Calculate wind component along the path
    # If Wind=90 (East), Course=90 (East), relative=0, cos(0)=1.
    # This represents a HEADWIND (flying East into an East wind).
    wind_component = wind_speed * math.cos(relative_angle)
    
    # BUG: This adds the component. 
    # If flying into the wind (Headwind), GS should decrease.
    # Currently: TAS + WindSpeed (faster). Should be: TAS - WindSpeed (slower).
    ground_speed = true_airspeed + wind_component
    
    return max(0, ground_speed)
PYEOF

# fuel.py - Bug: Reserve calculated in minutes not hours
cat > "$PROJECT_DIR/planner/fuel.py" << 'PYEOF'
def calculate_trip_fuel(distance_nm, ground_speed_kts, burn_rate_gph):
    """
    Calculate total fuel required in gallons.
    """
    if ground_speed_kts <= 0:
        return float('inf')
        
    flight_time_hours = distance_nm / ground_speed_kts
    trip_fuel = flight_time_hours * burn_rate_gph
    return trip_fuel

def calculate_reserve_fuel(burn_rate_gph, reserve_minutes=45):
    """
    Calculate reserve fuel required by regulation.
    Default reserve is 45 minutes at normal cruise burn.
    """
    # BUG: Multiplies gallons-per-HOUR by MINUTES directly.
    # Should divide minutes by 60 first to get hours.
    # Result is 60x too high.
    reserve_fuel = burn_rate_gph * reserve_minutes
    
    return reserve_fuel

def calculate_total_fuel_load(distance_nm, ground_speed_kts, burn_rate_gph):
    trip = calculate_trip_fuel(distance_nm, ground_speed_kts, burn_rate_gph)
    reserve = calculate_reserve_fuel(burn_rate_gph)
    return trip + reserve
PYEOF

cat > "$PROJECT_DIR/planner/__init__.py" << 'PYEOF'
# Flight Planner Package
PYEOF

# 5. Create Tests
cat > "$PROJECT_DIR/tests/conftest.py" << 'PYEOF'
import pytest
import csv
import os

@pytest.fixture
def airports():
    data = {}
    # Handle path being run from project root or tests dir
    base_path = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    path = os.path.join(base_path, 'data/airports.csv')
    
    if not os.path.exists(path):
        # Fallback if structure is different during test execution
        path = 'data/airports.csv'

    with open(path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            data[row['ident']] = {
                'lat': float(row['latitude_deg']),
                'lon': float(row['longitude_deg'])
            }
    return data
PYEOF

cat > "$PROJECT_DIR/tests/test_geo.py" << 'PYEOF'
import pytest
import math
from planner.geo import calculate_distance, calculate_bearing

def test_distance_jfk_lhr_nm(airports):
    # JFK to LHR is approx 2991 Nautical Miles
    jfk = airports['KJFK']
    lhr = airports['EGLL']
    dist = calculate_distance(jfk['lat'], jfk['lon'], lhr['lat'], lhr['lon'])
    
    # Tolerance of 2%
    assert 2930 < dist < 3050, f"Expected ~2991 NM, got {dist}. Check units (KM vs NM)?"

def test_distance_zero():
    dist = calculate_distance(0, 0, 0, 0)
    assert dist == 0

def test_bearing_north_east():
    # 0,0 to 1,1 should be 45 degrees
    b = calculate_bearing(0, 0, 1, 1)
    # Allow small floating point variance
    assert 44.0 < b < 46.0

def test_bearing_sw_quadrant():
    # 1,1 to 0,0 should be 225 degrees (SW)
    # The BUG (atan instead of atan2) will likely return 45 degrees
    b = calculate_bearing(1, 1, 0, 0)
    assert 224.0 < b < 226.0, f"Expected ~225 deg (SW), got {b}. Quadrant error?"

def test_bearing_exact_north():
    # 0,0 to 1,0 is North (0 deg)
    b = calculate_bearing(0, 0, 1, 0)
    assert abs(b - 0) < 0.1 or abs(b - 360) < 0.1

def test_bearing_exact_south():
    # 1,0 to 0,0 is South (180 deg)
    b = calculate_bearing(1, 0, 0, 0)
    assert abs(b - 180) < 0.1
PYEOF

cat > "$PROJECT_DIR/tests/test_wind.py" << 'PYEOF'
import pytest
from planner.wind import calculate_ground_speed

def test_ground_speed_calm():
    # No wind: GS == TAS
    gs = calculate_ground_speed(100, 90, 0, 0)
    assert gs == 100

def test_ground_speed_tailwind():
    # TAS 100, Course 090 (East), Wind from 270 (West) at 20
    # Tailwind of 20. GS should be 120.
    gs = calculate_ground_speed(100, 90, 20, 270)
    assert 119 < gs < 121

def test_ground_speed_headwind():
    # TAS 100, Course 090 (East), Wind from 090 (East) at 20
    # Headwind of 20. GS should be 80.
    # BUG: The code adds the component, so it returns 120.
    gs = calculate_ground_speed(100, 90, 20, 90)
    assert 79 < gs < 81, f"Expected 80 kts (Headwind), got {gs}. Sign error?"

def test_ground_speed_crosswind():
    # TAS 100, Course 360 (North), Wind from 090 (East) at 20
    # Pure crosswind. GS should be approx sqrt(100^2 - 20^2) approx 98 (simplified)
    # Actually, simplistic ground speed logic is often just TAS + component for estimation,
    # but strictly GS vector magnitude. The bug is about sign.
    # Component is 0 here (cos(90)=0). So GS should be 100 in simple approximation.
    gs = calculate_ground_speed(100, 360, 20, 90)
    assert 99 < gs < 101

def test_strong_wind_stop():
    # TAS 100, Headwind 100 -> GS 0
    gs = calculate_ground_speed(100, 90, 100, 90)
    assert gs == 0
PYEOF

cat > "$PROJECT_DIR/tests/test_fuel.py" << 'PYEOF'
import pytest
from planner.fuel import calculate_trip_fuel, calculate_reserve_fuel

def test_trip_fuel_simple():
    # 100 NM at 100 kts = 1 hour. Burn 10 gph -> 10 gal.
    fuel = calculate_trip_fuel(100, 100, 10)
    assert fuel == 10

def test_reserve_fuel_45min():
    # 45 mins at 10 gph
    # 45 mins = 0.75 hours. Fuel = 7.5 gallons.
    # BUG: returns 45 * 10 = 450 gallons.
    fuel = calculate_reserve_fuel(10)
    assert 7.0 < fuel < 8.0, f"Expected ~7.5 gal, got {fuel}. Time unit error?"

def test_reserve_fuel_custom():
    # 30 mins at 20 gph = 10 gallons
    fuel = calculate_reserve_fuel(20, 30)
    assert fuel == 10

def test_total_load():
    # Trip 10 gal, Reserve 7.5 gal -> 17.5 gal
    trip_dist = 100
    gs = 100
    burn = 10
    total = calculate_trip_fuel(trip_dist, gs, burn) + calculate_reserve_fuel(burn)
    assert total > 0
PYEOF

cat > "$PROJECT_DIR/requirements.txt" << 'REQEOF'
pytest
REQEOF

# 6. Set permissions
chown -R ga:ga "$PROJECT_DIR"

# 7. Record start time
date +%s > /tmp/flight_planner_start_ts

# 8. Start PyCharm
echo "Launching PyCharm..."
su - ga -c "DISPLAY=:1 /opt/pycharm/bin/pycharm.sh '$PROJECT_DIR' > /tmp/pycharm_launch.log 2>&1 &"

# 9. Wait for window and maximize
sleep 10
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "pycharm\|flight_planner"; then
        echo "PyCharm window found"
        break
    fi
    sleep 2
done

# Dismiss dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize
DISPLAY=:1 wmctrl -r "flight_planner" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "PyCharm" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 10. Initial Screenshot
DISPLAY=:1 scrot /tmp/flight_planner_initial.png 2>/dev/null || true

echo "=== Setup complete ==="