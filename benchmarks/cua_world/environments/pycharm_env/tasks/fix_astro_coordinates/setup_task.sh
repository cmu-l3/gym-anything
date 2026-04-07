#!/bin/bash
echo "=== Setting up fix_astro_coordinates task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="fix_astro_coordinates"
PROJECT_DIR="/home/ga/PycharmProjects/astro_coords"

# Clean previous state
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/${TASK_NAME}_result.json 2>/dev/null || true

# Create project structure
su - ga -c "mkdir -p $PROJECT_DIR/coords $PROJECT_DIR/tests $PROJECT_DIR/data"

# Create requirements.txt
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
pytest>=7.0
numpy>=1.24.0
EOF

# --- data/bright_stars.json ---
cat > "$PROJECT_DIR/data/bright_stars.json" << 'EOF'
[
  {
    "name": "Sirius",
    "ra_hms": "06:45:08.92",
    "dec_dms": "-16:42:58.0",
    "ra_deg": 101.28715,
    "dec_deg": -16.71611,
    "gal_l": 227.23,
    "gal_b": -8.89
  },
  {
    "name": "Vega",
    "ra_hms": "18:36:56.34",
    "dec_dms": "+38:47:01.3",
    "ra_deg": 279.23475,
    "dec_deg": 38.78369,
    "gal_l": 67.45,
    "gal_b": 19.24
  },
  {
    "name": "Polaris",
    "ra_hms": "02:31:49.09",
    "dec_dms": "+89:15:50.8",
    "ra_deg": 37.95454,
    "dec_deg": 89.26411,
    "gal_l": 123.28,
    "gal_b": 26.46
  },
  {
    "name": "Betelgeuse",
    "ra_hms": "05:55:10.31",
    "dec_dms": "+07:24:25.4",
    "ra_deg": 88.79296,
    "dec_deg": 7.40706,
    "gal_l": 199.79,
    "gal_b": -8.96
  }
]
EOF

# --- coords/__init__.py ---
touch "$PROJECT_DIR/coords/__init__.py"

# --- coords/conversions.py (Bug 4) ---
cat > "$PROJECT_DIR/coords/conversions.py" << 'EOF'
"""Coordinate format conversions (HMS/DMS <-> Degrees)."""
import math
from typing import Tuple

def hms_to_degrees(h: int, m: int, s: float) -> float:
    """Convert Hours:Minutes:Seconds to decimal degrees."""
    # RA in degrees = (H + M/60 + S/3600) * 15
    
    # BUG 4: Divides seconds by 60 instead of 3600
    # This makes seconds contribute 60x more than they should
    decimal_hours = h + m / 60.0 + s / 60.0
    
    return decimal_hours * 15.0

def dms_to_degrees(d: int, m: int, s: float) -> float:
    """Convert Degrees:Minutes:Seconds to decimal degrees."""
    sign = -1 if d < 0 else 1
    abs_d = abs(d)
    
    decimal = abs_d + m / 60.0 + s / 3600.0
    return sign * decimal

def degrees_to_radians(deg: float) -> float:
    """Convert degrees to radians."""
    return math.radians(deg)

def radians_to_degrees(rad: float) -> float:
    """Convert radians to degrees."""
    return math.degrees(rad)
EOF

# --- coords/transforms.py (Bug 1 & 2) ---
cat > "$PROJECT_DIR/coords/transforms.py" << 'EOF'
"""Coordinate frame transformations."""
import math
from typing import Tuple

def equatorial_to_galactic(ra_deg: float, dec_deg: float) -> Tuple[float, float]:
    """
    Convert Equatorial (J2000) to Galactic coordinates.
    Formulae from Meeus, Astronomical Algorithms.
    
    North Galactic Pole (NGP) J2000:
    RA_NGP = 192.85948 deg
    Dec_NGP = 27.12825 deg
    Ascending Node longitude = 122.93192 deg
    """
    ra_rad = math.radians(ra_deg)
    dec_rad = math.radians(dec_deg)
    
    # Constants for J2000 NGP
    # BUG 1: These constants are used directly in trig functions without conversion to radians
    # Only alpha_ngp is converted below (inconsistently), delta_ngp is NOT converted
    alpha_ngp = math.radians(192.85948)
    delta_ngp = 27.12825  # MISSING math.radians()
    l_node = math.radians(122.93192)
    
    # sin(b) = sin(dec)sin(dec_ngp) + cos(dec)cos(dec_ngp)cos(ra - ra_ngp)
    sin_b = math.sin(dec_rad) * math.sin(delta_ngp) + \
            math.cos(dec_rad) * math.cos(delta_ngp) * math.cos(ra_rad - alpha_ngp)
            
    b_rad = math.asin(sin_b)
    
    # cos(b) sin(l_cp - l) = cos(dec) sin(ra - ra_ngp)
    # cos(b) cos(l_cp - l) = sin(dec) cos(dec_ngp) - cos(dec) sin(dec_ngp) cos(ra - ra_ngp)
    
    y = math.cos(dec_rad) * math.sin(ra_rad - alpha_ngp)
    x = math.sin(dec_rad) * math.cos(delta_ngp) - \
        math.cos(dec_rad) * math.sin(delta_ngp) * math.cos(ra_rad - alpha_ngp)
        
    l_cp_minus_l = math.atan2(y, x)
    
    l_rad = l_node - l_cp_minus_l
    
    # Normalize to 0-360
    l_deg = math.degrees(l_rad) % 360.0
    b_deg = math.degrees(b_rad)
    
    return l_deg, b_deg

def equatorial_to_horizontal(ra_deg: float, dec_deg: float, 
                           lat_deg: float, lst_hours: float) -> Tuple[float, float]:
    """
    Convert Equatorial to Horizontal (Alt/Az) coordinates.
    """
    ra_rad = math.radians(ra_deg)
    dec_rad = math.radians(dec_deg)
    lat_rad = math.radians(lat_deg)
    
    # Local Hour Angle (LHA) = LST - RA
    # LST is in hours, convert to radians (15 deg/hour)
    lst_rad = math.radians(lst_hours * 15.0)
    ha_rad = lst_rad - ra_rad
    
    # sin(alt) = sin(dec)sin(lat) + cos(dec)cos(lat)cos(ha)
    sin_alt = math.sin(dec_rad) * math.sin(lat_rad) + \
              math.cos(dec_rad) * math.cos(lat_rad) * math.cos(ha_rad)
    alt_rad = math.asin(sin_alt)
    
    # tan(az) = sin(ha) / (cos(ha)sin(lat) - tan(dec)cos(lat))
    # Using atan2(y, x)
    y = math.sin(ha_rad)
    x = math.cos(ha_rad) * math.sin(lat_rad) - math.tan(dec_rad) * math.cos(lat_rad)
    
    # BUG 2: Arguments to atan2 are swapped. Should be atan2(y, x), is atan2(x, y)
    az_rad = math.atan2(x, y)
    
    alt_deg = math.degrees(alt_rad)
    az_deg = math.degrees(az_rad) % 360.0
    
    return alt_deg, az_deg
EOF

# --- coords/separation.py (Bug 3) ---
cat > "$PROJECT_DIR/coords/separation.py" << 'EOF'
"""Angular separation calculations."""
import math

def angular_separation(ra1_deg: float, dec1_deg: float, 
                      ra2_deg: float, dec2_deg: float) -> float:
    """
    Calculate angular separation between two points on the sphere.
    Uses spherical law of cosines.
    """
    ra1 = math.radians(ra1_deg)
    dec1 = math.radians(dec1_deg)
    ra2 = math.radians(ra2_deg)
    dec2 = math.radians(dec2_deg)
    
    # cos(sep) = sin(dec1)sin(dec2) + cos(dec1)cos(dec2)cos(ra1 - ra2)
    
    # BUG 3: Uses addition instead of subtraction in the cosine term
    # Should be cos(ra1 - ra2), code has cos(ra1 + ra2)
    cos_sep = math.sin(dec1) * math.sin(dec2) + \
              math.cos(dec1) * math.cos(dec2) * math.cos(ra1 + ra2)
              
    # Clamp for numerical stability
    cos_sep = max(min(cos_sep, 1.0), -1.0)
    
    sep_rad = math.acos(cos_sep)
    return math.degrees(sep_rad)
EOF

# --- tests/conftest.py ---
cat > "$PROJECT_DIR/tests/conftest.py" << 'EOF'
import pytest
import json
import os

@pytest.fixture
def star_data():
    data_path = os.path.join(os.path.dirname(__file__), '..', 'data', 'bright_stars.json')
    with open(data_path, 'r') as f:
        return json.load(f)

@pytest.fixture
def sirius(star_data):
    return next(s for s in star_data if s['name'] == 'Sirius')

@pytest.fixture
def vega(star_data):
    return next(s for s in star_data if s['name'] == 'Vega')
EOF

# --- tests/test_conversions.py ---
cat > "$PROJECT_DIR/tests/test_conversions.py" << 'EOF'
import pytest
from coords.conversions import hms_to_degrees, dms_to_degrees, degrees_to_radians, radians_to_degrees
import math

def test_deg_to_rad():
    assert degrees_to_radians(180) == pytest.approx(math.pi)

def test_rad_to_deg():
    assert radians_to_degrees(math.pi) == pytest.approx(180)

def test_parse_dms_positive():
    # 10:30:00 = 10.5 degrees
    assert dms_to_degrees(10, 30, 0) == pytest.approx(10.5)

def test_conversions_roundtrip_ra():
    # 12h 0m 0s = 180 degrees
    assert hms_to_degrees(12, 0, 0) == pytest.approx(180.0)

def test_parse_hms_sirius(sirius):
    # Sirius RA: 06h 45m 08.92s
    # Should be ~101.287 degrees
    # Bug 4 will cause this to fail because seconds are weighted 60x too high
    h, m, s = 6, 45, 8.92
    expected = 101.28715
    assert hms_to_degrees(h, m, s) == pytest.approx(expected, abs=0.001)
EOF

# --- tests/test_transforms.py ---
cat > "$PROJECT_DIR/tests/test_transforms.py" << 'EOF'
import pytest
from coords.transforms import equatorial_to_galactic, equatorial_to_horizontal

def test_equatorial_to_galactic_vega(vega):
    # Vega is often used as a standard candle/reference
    l, b = equatorial_to_galactic(vega['ra_deg'], vega['dec_deg'])
    assert l == pytest.approx(vega['gal_l'], abs=0.1)
    assert b == pytest.approx(vega['gal_b'], abs=0.1)

def test_equatorial_to_galactic_sirius(sirius):
    # Bug 1 (degrees in sin/cos) causes this to be wildly off
    l, b = equatorial_to_galactic(sirius['ra_deg'], sirius['dec_deg'])
    assert l == pytest.approx(sirius['gal_l'], abs=0.1)
    assert b == pytest.approx(sirius['gal_b'], abs=0.1)

def test_equatorial_to_galactic_polaris(star_data):
    polaris = next(s for s in star_data if s['name'] == 'Polaris')
    l, b = equatorial_to_galactic(polaris['ra_deg'], polaris['dec_deg'])
    assert l == pytest.approx(polaris['gal_l'], abs=0.1)
    assert b == pytest.approx(polaris['gal_b'], abs=0.1)

def test_horizontal_altitude_zenith():
    # Object at Zenith (Alt=90)
    # Observer at lat=30, LST=0. Object at RA=0, Dec=30
    alt, az = equatorial_to_horizontal(0, 30, 30, 0)
    assert alt == pytest.approx(90.0, abs=0.01)

def test_equatorial_to_horizontal_vega():
    # Known benchmark: Vega at McDonald Observatory
    # Lat = 30.6714 N
    # LST = 18.6156 hours (chosen so HA = 0 approx)
    # Vega RA = 18.6156 h -> HA = 0
    # Dec = 38.7837
    # At HA=0, Azimuth should be 0 (North) or 180 (South) depending on convention
    # With HA=0, it's on meridian.
    # Lat (30.7) < Dec (38.8), so it's North of Zenith.
    # Azimuth should be 0 (North).
    # Bug 2 (swapped atan2) will likely give Az = 90 or 270 or something else
    
    ra = 279.234  # 18.6156h
    dec = 38.784
    lat = 30.6714
    lst = 18.6156
    
    alt, az = equatorial_to_horizontal(ra, dec, lat, lst)
    
    # Alt should be 90 - (Dec - Lat) = 90 - (38.78 - 30.67) = 81.89
    expected_alt = 90 - (dec - lat)
    
    assert alt == pytest.approx(expected_alt, abs=0.1)
    # Azimuth 0 (North)
    assert az == pytest.approx(0.0, abs=1.0)
EOF

# --- tests/test_separation.py ---
cat > "$PROJECT_DIR/tests/test_separation.py" << 'EOF'
import pytest
from coords.separation import angular_separation

def test_separation_identical_points():
    assert angular_separation(100, 20, 100, 20) == pytest.approx(0.0)

def test_separation_poles():
    # North pole to South pole = 180 degrees
    # RA doesn't matter at poles
    assert angular_separation(0, 90, 0, -90) == pytest.approx(180.0)

def test_separation_close_stars():
    # Two points on equator, 1 degree apart in RA
    # Bug 3 (addition instead of subtraction): cos(ra1+ra2) vs cos(ra1-ra2)
    # ra1=100, ra2=101. 
    # Correct: cos(1) -> sep ~ 1 deg
    # Buggy: cos(201) -> sep is huge
    sep = angular_separation(100, 0, 101, 0)
    assert sep == pytest.approx(1.0, abs=0.01)

def test_separation_sirius_betelgeuse(sirius, star_data):
    betelgeuse = next(s for s in star_data if s['name'] == 'Betelgeuse')
    
    # Reference separation between Sirius and Betelgeuse is approx 27.1 degrees
    sep = angular_separation(sirius['ra_deg'], sirius['dec_deg'],
                           betelgeuse['ra_deg'], betelgeuse['dec_deg'])
                           
    assert sep == pytest.approx(27.1, abs=0.5)
EOF

# Install/Verify PyCharm project setup
echo "Configuring project..."
# Make sure project dir is owned by ga
chown -R ga:ga "$PROJECT_DIR"

# Record timestamp for anti-gaming
date +%s > /tmp/${TASK_NAME}_start_ts

# Launch PyCharm
echo "Launching PyCharm..."
setup_pycharm_project "$PROJECT_DIR" "astro_coords" 120

# Take screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="