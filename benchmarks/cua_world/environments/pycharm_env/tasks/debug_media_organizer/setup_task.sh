#!/bin/bash
echo "=== Setting up debug_media_organizer task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="debug_media_organizer"
PROJECT_DIR="/home/ga/PycharmProjects/media_organizer"

# Clean any previous state
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/${TASK_NAME}_start_ts /tmp/${TASK_NAME}_result.json

# Create project structure
su - ga -c "mkdir -p $PROJECT_DIR/organizer $PROJECT_DIR/tests"

# --- requirements.txt ---
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
pytest>=7.0
Pillow>=9.0.0
EOF

# --- organizer/__init__.py ---
touch "$PROJECT_DIR/organizer/__init__.py"

# --- organizer/utils.py ---
cat > "$PROJECT_DIR/organizer/utils.py" << 'EOF'
"""Utility functions for file handling."""
import os

def ensure_directory(path):
    """Ensure a directory exists."""
    if not os.path.exists(path):
        os.makedirs(path)
EOF

# --- organizer/metadata.py (CONTAINS BUGS 1 & 2) ---
cat > "$PROJECT_DIR/organizer/metadata.py" << 'EOF'
"""Metadata extraction logic for media files."""
from datetime import datetime
from PIL import Image
from PIL.ExifTags import TAGS, GPSTAGS

def get_exif_data(image_path):
    """Return a dictionary from the exif data of an PIL Image item."""
    exif_data = {}
    try:
        image = Image.open(image_path)
        info = image._getexif()
        if info:
            for tag, value in info.items():
                decoded = TAGS.get(tag, tag)
                if decoded == "GPSInfo":
                    gps_data = {}
                    for t in value:
                        sub_decoded = GPSTAGS.get(t, t)
                        gps_data[sub_decoded] = value[t]
                    exif_data[decoded] = gps_data
                else:
                    exif_data[decoded] = value
    except Exception:
        pass
    return exif_data

def _convert_to_degrees(value):
    """Helper to convert GPS coordinates to degrees."""
    d = float(value[0])
    m = float(value[1])
    s = float(value[2])
    return d + (m / 60.0) + (s / 3600.0)

def get_decimal_coordinates(gps_info):
    """
    Convert GPS info dict to decimal coordinates (lat, lon).
    Returns (None, None) if info is missing.
    """
    if not gps_info:
        return None, None
    
    # GPSLatitude is tag 2, GPSLongitude is tag 4
    # GPSLatitudeRef is tag 1, GPSLongitudeRef is tag 3
    # Note: In the parsed dict from Pillow, keys might be strings if GPSTAGS mapped them
    
    # Check for keys (Pillow usually maps them to names like 'GPSLatitude')
    lat_raw = gps_info.get('GPSLatitude') or gps_info.get(2)
    lon_raw = gps_info.get('GPSLongitude') or gps_info.get(4)
    
    lat_ref = gps_info.get('GPSLatitudeRef') or gps_info.get(1)
    lon_ref = gps_info.get('GPSLongitudeRef') or gps_info.get(3)
    
    if not lat_raw or not lon_raw:
        return None, None
        
    lat = _convert_to_degrees(lat_raw)
    lon = _convert_to_degrees(lon_raw)
    
    # BUG 1: GPS Sign Error
    # The code calculates magnitude but ignores the Hemisphere reference ('S' or 'W').
    # It should negate the value if ref is 'S' or 'W'.
    # CURRENTLY MISSING: logic to check lat_ref/lon_ref and multiply by -1
    
    return lat, lon

def extract_date(exif_data):
    """
    Extract the creation date from EXIF data.
    Returns datetime object or None.
    """
    # DateTimeOriginal is standard tag 36867
    date_str = exif_data.get('DateTimeOriginal')
    
    if not date_str:
        return None
        
    try:
        # BUG 2: Date Parsing Fragility
        # Standard EXIF is "YYYY:MM:DD HH:MM:SS", but some softwares/cameras use "-" or "/"
        # This will crash or fail on non-standard delimiters.
        return datetime.strptime(date_str, "%Y:%m:%d %H:%M:%S")
    except ValueError:
        return None
EOF

# --- organizer/core.py (CONTAINS BUG 3) ---
cat > "$PROJECT_DIR/organizer/core.py" << 'EOF'
"""Core organization logic."""
import os
import shutil
from .metadata import get_exif_data, extract_date, get_decimal_coordinates
from .utils import ensure_directory

def organize_file(src_path, dest_root, simulate=False):
    """
    Move a file to dest_root/YYYY/MM/filename.ext based on EXIF date.
    Returns the destination path.
    """
    if not os.path.exists(src_path):
        raise FileNotFoundError(f"Source file {src_path} not found")
        
    exif = get_exif_data(src_path)
    date_obj = extract_date(exif)
    
    if not date_obj:
        # Fallback for no date: put in 'Unknown' folder
        year = "Unknown"
        month = "Unknown"
    else:
        year = str(date_obj.year)
        month = f"{date_obj.month:02d}"
        
    dest_dir = os.path.join(dest_root, year, month)
    
    filename = os.path.basename(src_path)
    dest_path = os.path.join(dest_dir, filename)
    
    if not simulate:
        ensure_directory(dest_dir)
        
        # BUG 3: Unsafe File Move
        # If dest_path exists, shutil.move will overwrite it (on many systems) or fail.
        # Requirement: Check existence and rename (e.g., img.jpg -> img_1.jpg)
        
        print(f"Moving {src_path} to {dest_path}")
        shutil.move(src_path, dest_path)
        
    return dest_path
EOF

# --- tests/conftest.py ---
cat > "$PROJECT_DIR/tests/conftest.py" << 'EOF'
import pytest
import os
import shutil
from PIL import Image

@pytest.fixture
def temp_workspace(tmp_path):
    """Create a temp workspace with source and dest folders."""
    src = tmp_path / "source"
    dest = tmp_path / "dest"
    src.mkdir()
    dest.mkdir()
    return src, dest

@pytest.fixture
def mock_exif_gps_west():
    """Mock GPS data for a location in Western Hemisphere (New York)."""
    # 40 deg 42' 46" N, 74 deg 0' 21" W
    # Lat: 40.7128, Lon: -74.0060
    return {
        'GPSLatitude': (40.0, 42.0, 46.0),
        'GPSLatitudeRef': 'N',
        'GPSLongitude': (74.0, 0.0, 21.0),
        'GPSLongitudeRef': 'W'
    }

@pytest.fixture
def mock_exif_gps_south():
    """Mock GPS data for a location in Southern Hemisphere (Sydney)."""
    # 33 deg 51' 54" S, 151 deg 12' 36" E
    # Lat: -33.865, Lon: 151.21
    return {
        'GPSLatitude': (33.0, 51.0, 54.0),
        'GPSLatitudeRef': 'S',
        'GPSLongitude': (151.0, 12.0, 36.0),
        'GPSLongitudeRef': 'E'
    }
EOF

# --- tests/test_metadata.py ---
cat > "$PROJECT_DIR/tests/test_metadata.py" << 'EOF'
import pytest
from datetime import datetime
from organizer.metadata import get_decimal_coordinates, extract_date

def test_gps_simple_conversion():
    # 10 deg 30 min 0 sec -> 10.5
    info = {
        'GPSLatitude': (10.0, 30.0, 0.0), 'GPSLatitudeRef': 'N',
        'GPSLongitude': (10.0, 30.0, 0.0), 'GPSLongitudeRef': 'E'
    }
    lat, lon = get_decimal_coordinates(info)
    assert lat == 10.5
    assert lon == 10.5

def test_gps_west_location(mock_exif_gps_west):
    """Test that West longitudes are negative."""
    lat, lon = get_decimal_coordinates(mock_exif_gps_west)
    # Allow small float error
    assert lat > 0, "NY Latitude should be positive (N)"
    assert lon < 0, "NY Longitude should be negative (W)"
    assert abs(lon + 74.0058) < 0.01

def test_gps_south_location(mock_exif_gps_south):
    """Test that South latitudes are negative."""
    lat, lon = get_decimal_coordinates(mock_exif_gps_south)
    assert lat < 0, "Sydney Latitude should be negative (S)"
    assert lon > 0, "Sydney Longitude should be positive (E)"
    assert abs(lat + 33.865) < 0.01

def test_date_standard_format():
    data = {'DateTimeOriginal': '2023:10:25 14:30:00'}
    dt = extract_date(data)
    assert dt == datetime(2023, 10, 25, 14, 30, 0)

def test_date_with_dashes():
    """Test robustness against dash separators."""
    data = {'DateTimeOriginal': '2023-10-25 14:30:00'}
    dt = extract_date(data)
    assert dt is not None
    assert dt == datetime(2023, 10, 25, 14, 30, 0)

def test_date_with_slashes():
    """Test robustness against slash separators."""
    data = {'DateTimeOriginal': '2023/10/25 14:30:00'}
    dt = extract_date(data)
    assert dt is not None
    assert dt == datetime(2023, 10, 25, 14, 30, 0)
EOF

# --- tests/test_core.py ---
cat > "$PROJECT_DIR/tests/test_core.py" << 'EOF'
import os
import pytest
from unittest.mock import patch
from datetime import datetime
from organizer.core import organize_file

# Mock data for organize file tests
MOCK_EXIF = {
    'DateTimeOriginal': '2023:05:15 10:00:00'
}

@patch('organizer.core.get_exif_data', return_value=MOCK_EXIF)
def test_organize_moves_file_correctly(mock_exif, temp_workspace):
    src, dest = temp_workspace
    
    # Create source file
    src_file = src / "test_img.jpg"
    src_file.write_text("dummy content")
    
    # Run
    new_path = organize_file(str(src_file), str(dest))
    
    # Check basics
    assert os.path.exists(new_path)
    assert not os.path.exists(src_file)
    assert "2023/05" in new_path

@patch('organizer.core.get_exif_data', return_value=MOCK_EXIF)
def test_no_overwrite_on_conflict(mock_exif, temp_workspace):
    src, dest = temp_workspace
    
    # Setup: Destination file ALREADY exists with different content
    dest_dir = dest / "2023" / "05"
    dest_dir.mkdir(parents=True)
    existing_file = dest_dir / "test_img.jpg"
    existing_file.write_text("ORIGINAL CONTENT")
    
    # Source file with same name but new content
    src_file = src / "test_img.jpg"
    src_file.write_text("NEW CONTENT")
    
    # Run
    new_path = organize_file(str(src_file), str(dest))
    
    # Verify:
    # 1. Original file is untouched
    assert existing_file.read_text() == "ORIGINAL CONTENT"
    
    # 2. New file exists at a DIFFERENT path (renamed)
    assert new_path != str(existing_file)
    assert os.path.exists(new_path)
    assert os.path.basename(new_path).startswith("test_img")
    
    # 3. New file has correct content
    with open(new_path, 'r') as f:
        content = f.read()
    assert content == "NEW CONTENT"
EOF

# Record start time
date +%s > /tmp/debug_media_organizer_start_ts

# Setup complete
echo "Task setup complete. Project created at $PROJECT_DIR"