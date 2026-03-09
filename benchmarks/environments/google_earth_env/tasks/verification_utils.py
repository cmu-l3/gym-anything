"""
Robust verification utilities for Google Earth Pro tasks.

This module provides reliable methods for extracting state from Google Earth
without relying on easily-gameable signals like keyword matching or
agent-writable files.

Key principles:
1. Extract actual coordinates from Google Earth (not just keywords)
2. Use multiple independent extraction methods
3. Verify process integrity to prevent spoofing
4. Use AND logic (all conditions must pass) not OR logic
5. Never trust agent-writable files like /tmp/task_result.txt
"""

import os
import subprocess
import json
import re
import time
import hashlib
import tempfile
from pathlib import Path
from typing import Optional, Tuple, Dict, Any, List
from dataclasses import dataclass, field


# ============================================================================
# DATA STRUCTURES
# ============================================================================

@dataclass
class ViewState:
    """Represents extracted view state from Google Earth."""
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    altitude: Optional[float] = None  # Camera altitude/range in meters
    heading: Optional[float] = None
    tilt: Optional[float] = None
    source: str = ""
    confidence: float = 0.0
    raw_data: Dict[str, Any] = field(default_factory=dict)


@dataclass
class PlacemarkInfo:
    """Represents a placemark extracted from KML."""
    name: str = ""
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    altitude: Optional[float] = None
    description: str = ""
    raw_xml: str = ""


@dataclass
class MeasurementInfo:
    """Represents a measurement/path extracted from KML."""
    name: str = ""
    coordinates: List[Tuple[float, float, float]] = field(default_factory=list)  # (lon, lat, alt)
    distance_meters: Optional[float] = None
    raw_xml: str = ""


@dataclass
class ImageMetadata:
    """Represents metadata extracted from an image file."""
    filepath: str = ""
    width: Optional[int] = None
    height: Optional[int] = None
    gps_latitude: Optional[float] = None
    gps_longitude: Optional[float] = None
    gps_altitude: Optional[float] = None
    software: str = ""
    creation_time: Optional[str] = None
    has_gps: bool = False


# ============================================================================
# CONSTANTS
# ============================================================================

GOOGLE_EARTH_STATE_DIR = Path('/home/ga/.googleearth')
GOOGLE_EARTH_CONFIG_DIR = Path('/home/ga/.config/Google')


# ============================================================================
# PROCESS INTEGRITY VERIFICATION
# ============================================================================

def get_google_earth_pid() -> Optional[int]:
    """Get the PID of the Google Earth process."""
    try:
        result = subprocess.run(
            ['pgrep', '-f', 'google-earth-pro'],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            pids = result.stdout.strip().split('\n')
            if pids and pids[0]:
                return int(pids[0])
    except Exception:
        pass
    return None


def get_google_earth_window_id() -> Optional[str]:
    """Get the window ID of Google Earth Pro specifically."""
    try:
        result = subprocess.run(
            ['wmctrl', '-l'],
            capture_output=True,
            text=True,
            timeout=5
        )
        for line in result.stdout.splitlines():
            if 'Google Earth Pro' in line or 'Google Earth' in line:
                return line.split()[0]
    except Exception:
        pass
    return None


def is_google_earth_running() -> bool:
    """Check if Google Earth Pro is running with proper verification."""
    pid = get_google_earth_pid()
    if not pid:
        return False

    # Verify it's actually Google Earth binary
    try:
        exe_path = os.readlink(f'/proc/{pid}/exe')
        return 'google-earth' in exe_path.lower()
    except Exception:
        return False


def verify_process_integrity() -> Dict[str, Any]:
    """
    Comprehensive verification that Google Earth is running legitimately.
    Returns dict with detailed integrity check results.
    """
    checks = {
        'process_exists': False,
        'correct_binary': False,
        'has_window': False,
        'window_responsive': False,
        'pid': None,
        'binary_path': None,
        'window_id': None
    }

    try:
        # Check 1: Process exists
        pid = get_google_earth_pid()
        checks['pid'] = pid
        checks['process_exists'] = pid is not None

        if pid:
            # Check 2: Verify binary path
            try:
                exe_path = os.readlink(f'/proc/{pid}/exe')
                checks['binary_path'] = exe_path
                checks['correct_binary'] = 'google-earth' in exe_path.lower()
            except Exception:
                pass

        # Check 3: Window exists
        window_id = get_google_earth_window_id()
        checks['window_id'] = window_id
        checks['has_window'] = window_id is not None

        # Check 4: Window is responsive (can get properties)
        if window_id:
            result = subprocess.run(
                ['xprop', '-id', window_id, 'WM_STATE'],
                capture_output=True,
                timeout=5
            )
            checks['window_responsive'] = result.returncode == 0

    except Exception:
        pass

    return checks


def focus_google_earth_window() -> bool:
    """Focus the Google Earth window and verify it's focused."""
    window_id = get_google_earth_window_id()
    if not window_id:
        return False

    try:
        # Focus by window ID (more reliable)
        subprocess.run(['wmctrl', '-i', '-a', window_id], timeout=5)
        time.sleep(0.5)

        # Verify focus
        result = subprocess.run(
            ['xdotool', 'getactivewindow'],
            capture_output=True,
            text=True,
            timeout=5
        )
        active_id = result.stdout.strip()

        # Convert hex formats for comparison
        if window_id.startswith('0x'):
            window_id_int = int(window_id, 16)
        else:
            window_id_int = int(window_id)

        return int(active_id) == window_id_int

    except Exception:
        return False


# ============================================================================
# COORDINATE EXTRACTION METHODS
# ============================================================================

def extract_coordinates_via_status_bar_ocr() -> ViewState:
    """
    Extract coordinates by OCRing Google Earth's status bar.

    The status bar shows cursor coordinates. By moving the mouse to
    the center of the view, we can read the center coordinates.

    This is the most direct method - reads what Google Earth displays.
    """
    state = ViewState(source="status_bar_ocr")

    try:
        if not focus_google_earth_window():
            state.raw_data['error'] = 'Could not focus Google Earth window'
            return state

        window_id = get_google_earth_window_id()
        if not window_id:
            return state

        # Get window geometry
        result = subprocess.run(
            ['xdotool', 'getwindowgeometry', window_id],
            capture_output=True,
            text=True,
            timeout=5
        )

        # Parse geometry: "Window 12345678\n  Position: X,Y\n  Geometry: WxH"
        pos_match = re.search(r'Position:\s*(\d+),(\d+)', result.stdout)
        geo_match = re.search(r'Geometry:\s*(\d+)x(\d+)', result.stdout)

        if not geo_match:
            state.raw_data['error'] = 'Could not get window geometry'
            return state

        width, height = int(geo_match.group(1)), int(geo_match.group(2))
        win_x, win_y = 0, 0
        if pos_match:
            win_x, win_y = int(pos_match.group(1)), int(pos_match.group(2))

        # Move mouse to center of window to show center coordinates
        center_x = win_x + width // 2
        center_y = win_y + height // 2

        subprocess.run(['xdotool', 'mousemove', str(center_x), str(center_y)], timeout=5)
        time.sleep(0.5)  # Wait for status bar to update

        # Take screenshot
        with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as tmp:
            screenshot_path = tmp.name

        subprocess.run(['scrot', screenshot_path], timeout=10)

        # Crop to status bar (bottom 60 pixels)
        cropped_path = screenshot_path.replace('.png', '_statusbar.png')
        subprocess.run([
            'convert', screenshot_path,
            '-gravity', 'South',
            '-crop', f'{width}x60+0+0',
            '+repage',
            cropped_path
        ], timeout=10)

        # OCR the status bar
        result = subprocess.run(
            ['tesseract', cropped_path, 'stdout',
             '--psm', '7',  # Single line mode
             '-l', 'eng'],
            capture_output=True,
            text=True,
            timeout=30
        )
        ocr_text = result.stdout
        state.raw_data['ocr_text'] = ocr_text

        # Try to parse coordinates
        coords = parse_coordinates_from_text(ocr_text)
        if coords:
            state.latitude, state.longitude = coords
            state.confidence = 0.85

        # Cleanup
        for f in [screenshot_path, cropped_path]:
            if os.path.exists(f):
                os.unlink(f)

    except Exception as e:
        state.raw_data['error'] = str(e)
        state.confidence = 0.0

    return state


def extract_coordinates_via_clipboard() -> ViewState:
    """
    Extract coordinates by copying current view KML to clipboard.

    Google Earth copies a KML snippet when you press Ctrl+C with the
    3D view focused.
    """
    state = ViewState(source="clipboard_kml")

    try:
        if not focus_google_earth_window():
            state.raw_data['error'] = 'Could not focus Google Earth window'
            return state

        # Clear clipboard
        subprocess.run(
            ['xclip', '-selection', 'clipboard', '-i'],
            input=b'',
            timeout=5
        )

        time.sleep(0.3)

        # Send Ctrl+C to copy current view
        subprocess.run(['xdotool', 'key', 'ctrl+c'], timeout=5)
        time.sleep(0.5)

        # Read clipboard
        result = subprocess.run(
            ['xclip', '-selection', 'clipboard', '-o'],
            capture_output=True,
            text=True,
            timeout=5
        )
        clipboard_content = result.stdout
        state.raw_data['clipboard_content'] = clipboard_content[:500]

        # Parse KML from clipboard
        if '<LookAt>' in clipboard_content or '<Camera>' in clipboard_content:
            view = parse_lookat_from_kml(clipboard_content)
            if view.latitude is not None:
                state.latitude = view.latitude
                state.longitude = view.longitude
                state.altitude = view.altitude
                state.heading = view.heading
                state.tilt = view.tilt
                state.confidence = 0.9

    except Exception as e:
        state.raw_data['error'] = str(e)
        state.confidence = 0.0

    return state


def extract_coordinates_via_kml_export() -> ViewState:
    """
    Extract coordinates by automating KML export from Google Earth.

    Uses keyboard automation to trigger File → Save → Save Place As
    """
    state = ViewState(source="kml_export")

    try:
        if not focus_google_earth_window():
            state.raw_data['error'] = 'Could not focus Google Earth window'
            return state

        # Create temp file for KML
        kml_path = '/tmp/ge_view_export.kml'
        if os.path.exists(kml_path):
            os.unlink(kml_path)

        # Try keyboard shortcut first (Ctrl+S often opens save dialog)
        # Then navigate to save location
        subprocess.run(['xdotool', 'key', 'ctrl+s'], timeout=5)
        time.sleep(1)

        # Type the file path and save
        subprocess.run(['xdotool', 'type', '--clearmodifiers', kml_path], timeout=5)
        time.sleep(0.3)
        subprocess.run(['xdotool', 'key', 'Return'], timeout=5)
        time.sleep(2)

        # Check if file was created
        if os.path.exists(kml_path):
            content = Path(kml_path).read_text()
            state.raw_data['kml_content'] = content[:1000]

            view = parse_lookat_from_kml(content)
            if view.latitude is not None:
                state.latitude = view.latitude
                state.longitude = view.longitude
                state.altitude = view.altitude
                state.confidence = 0.9

            os.unlink(kml_path)
        else:
            state.raw_data['error'] = 'KML file was not created'

    except Exception as e:
        state.raw_data['error'] = str(e)
        state.confidence = 0.0

    return state


def extract_coordinates_via_config() -> ViewState:
    """
    Extract last known coordinates from Google Earth config files.

    Note: This requires Google Earth to have been closed gracefully,
    or the config to have been saved.
    """
    state = ViewState(source="config_file")

    config_paths = [
        GOOGLE_EARTH_CONFIG_DIR / 'GoogleEarthPro.conf',
        GOOGLE_EARTH_STATE_DIR / 'GoogleEarth.conf',
    ]

    try:
        for config_path in config_paths:
            if not config_path.exists():
                continue

            content = config_path.read_text()
            state.raw_data['config_path'] = str(config_path)

            # Look for view coordinates in various formats
            # Format 1: lat=48.858, lon=2.294
            lat_match = re.search(r'[Ll]at(?:itude)?[=:\s]+([-\d.]+)', content)
            lon_match = re.search(r'[Ll]on(?:gitude)?[=:\s]+([-\d.]+)', content)

            if lat_match and lon_match:
                state.latitude = float(lat_match.group(1))
                state.longitude = float(lon_match.group(1))
                state.confidence = 0.7
                break

            # Format 2: KML-style in config
            view = parse_lookat_from_kml(content)
            if view.latitude is not None:
                state.latitude = view.latitude
                state.longitude = view.longitude
                state.altitude = view.altitude
                state.confidence = 0.7
                break

    except Exception as e:
        state.raw_data['error'] = str(e)
        state.confidence = 0.0

    return state


def extract_coordinates_multiple_methods() -> Tuple[Optional[ViewState], List[ViewState]]:
    """
    Extract coordinates using multiple methods and return the best result.

    Returns:
        Tuple of (best_result, all_results)
    """
    results = []

    # Method 1: Clipboard (fastest, high confidence)
    results.append(extract_coordinates_via_clipboard())

    # Method 2: Status bar OCR (direct reading, good confidence)
    results.append(extract_coordinates_via_status_bar_ocr())

    # Filter to valid results
    valid_results = [r for r in results if r.latitude is not None and r.longitude is not None]

    if not valid_results:
        return None, results

    # Return highest confidence result
    best = max(valid_results, key=lambda x: x.confidence)
    return best, results


# ============================================================================
# KML PARSING UTILITIES
# ============================================================================

def parse_lookat_from_kml(kml_content: str) -> ViewState:
    """Parse <LookAt> or <Camera> element from KML content."""
    state = ViewState(source="kml_parse")

    try:
        # Try LookAt first
        lat_match = re.search(r'<latitude>([-\d.]+)</latitude>', kml_content)
        lon_match = re.search(r'<longitude>([-\d.]+)</longitude>', kml_content)

        if lat_match and lon_match:
            state.latitude = float(lat_match.group(1))
            state.longitude = float(lon_match.group(1))

            # Optional fields
            range_match = re.search(r'<range>([\d.]+)</range>', kml_content)
            alt_match = re.search(r'<altitude>([-\d.]+)</altitude>', kml_content)
            heading_match = re.search(r'<heading>([-\d.]+)</heading>', kml_content)
            tilt_match = re.search(r'<tilt>([-\d.]+)</tilt>', kml_content)

            if range_match:
                state.altitude = float(range_match.group(1))
            elif alt_match:
                state.altitude = float(alt_match.group(1))
            if heading_match:
                state.heading = float(heading_match.group(1))
            if tilt_match:
                state.tilt = float(tilt_match.group(1))

            state.confidence = 0.95

    except Exception:
        pass

    return state


def parse_coordinates_from_text(text: str) -> Optional[Tuple[float, float]]:
    """
    Parse latitude/longitude from text (e.g., OCR output).

    Handles formats:
    - DMS: 48°51'29.88"N 2°17'40.20"E
    - Decimal: 48.8584°N 2.2945°E
    - Plain decimal: 48.8584 2.2945
    """

    # Clean up OCR artifacts
    text = text.replace('|', '').replace('°', '°').replace("'", "'")

    # Pattern 1: DMS format
    dms_pattern = r"(\d+)[°](\d+)['\'](\d+\.?\d*)[\"\"]*\s*([NSns]).*?(\d+)[°](\d+)['\'](\d+\.?\d*)[\"\"]*\s*([EWew])"
    dms_match = re.search(dms_pattern, text)

    if dms_match:
        lat_d, lat_m, lat_s, lat_dir = dms_match.groups()[:4]
        lon_d, lon_m, lon_s, lon_dir = dms_match.groups()[4:]

        lat = float(lat_d) + float(lat_m)/60 + float(lat_s)/3600
        if lat_dir.upper() == 'S':
            lat = -lat

        lon = float(lon_d) + float(lon_m)/60 + float(lon_s)/3600
        if lon_dir.upper() == 'W':
            lon = -lon

        return (lat, lon)

    # Pattern 2: Decimal degrees with direction
    decimal_dir_pattern = r"([-]?\d+\.?\d*)[°]?\s*([NSns])\s+([-]?\d+\.?\d*)[°]?\s*([EWew])"
    decimal_match = re.search(decimal_dir_pattern, text)

    if decimal_match:
        lat = float(decimal_match.group(1))
        lon = float(decimal_match.group(3))
        if decimal_match.group(2).upper() == 'S':
            lat = -lat
        if decimal_match.group(4).upper() == 'W':
            lon = -lon
        return (lat, lon)

    # Pattern 3: Plain decimal (lat, lon)
    plain_pattern = r"([-]?\d+\.\d+)[,\s]+([-]?\d+\.\d+)"
    plain_match = re.search(plain_pattern, text)

    if plain_match:
        lat = float(plain_match.group(1))
        lon = float(plain_match.group(2))
        # Sanity check
        if -90 <= lat <= 90 and -180 <= lon <= 180:
            return (lat, lon)

    return None


def parse_placemarks_from_kml(kml_content: str) -> List[PlacemarkInfo]:
    """Parse all Placemark elements from KML content."""
    placemarks = []

    try:
        import xml.etree.ElementTree as ET

        # Handle KML namespace
        kml_content = re.sub(r'xmlns="[^"]*"', '', kml_content)
        root = ET.fromstring(kml_content)

        for pm_elem in root.iter('Placemark'):
            pm = PlacemarkInfo()

            # Get name
            name_elem = pm_elem.find('.//name')
            if name_elem is not None and name_elem.text:
                pm.name = name_elem.text.strip()

            # Get description
            desc_elem = pm_elem.find('.//description')
            if desc_elem is not None and desc_elem.text:
                pm.description = desc_elem.text.strip()

            # Get coordinates (from Point or LookAt)
            coord_elem = pm_elem.find('.//coordinates')
            if coord_elem is not None and coord_elem.text:
                coords_text = coord_elem.text.strip()
                # Format: lon,lat,alt or lon,lat
                parts = coords_text.split(',')
                if len(parts) >= 2:
                    pm.longitude = float(parts[0])
                    pm.latitude = float(parts[1])
                    if len(parts) >= 3:
                        pm.altitude = float(parts[2])

            # Store raw XML for debugging
            pm.raw_xml = ET.tostring(pm_elem, encoding='unicode')[:500]

            placemarks.append(pm)

    except Exception:
        # Fallback to regex parsing
        placemark_pattern = r'<Placemark>(.*?)</Placemark>'
        for match in re.finditer(placemark_pattern, kml_content, re.DOTALL):
            pm_xml = match.group(1)
            pm = PlacemarkInfo()
            pm.raw_xml = pm_xml[:500]

            name_match = re.search(r'<name>([^<]*)</name>', pm_xml)
            if name_match:
                pm.name = name_match.group(1).strip()

            coord_match = re.search(r'<coordinates>\s*([-\d.]+),([-\d.]+)(?:,([-\d.]+))?\s*</coordinates>', pm_xml)
            if coord_match:
                pm.longitude = float(coord_match.group(1))
                pm.latitude = float(coord_match.group(2))
                if coord_match.group(3):
                    pm.altitude = float(coord_match.group(3))

            placemarks.append(pm)

    return placemarks


def parse_paths_from_kml(kml_content: str) -> List[MeasurementInfo]:
    """Parse LineString/Path elements from KML (used for measurements)."""
    paths = []

    try:
        import xml.etree.ElementTree as ET

        kml_content = re.sub(r'xmlns="[^"]*"', '', kml_content)
        root = ET.fromstring(kml_content)

        # Look for Placemarks containing LineString
        for pm_elem in root.iter('Placemark'):
            linestring = pm_elem.find('.//LineString')
            if linestring is None:
                continue

            measurement = MeasurementInfo()

            # Get name
            name_elem = pm_elem.find('.//name')
            if name_elem is not None and name_elem.text:
                measurement.name = name_elem.text.strip()

            # Get coordinates
            coord_elem = linestring.find('coordinates')
            if coord_elem is not None and coord_elem.text:
                coords_text = coord_elem.text.strip()
                for point in coords_text.split():
                    parts = point.split(',')
                    if len(parts) >= 2:
                        lon = float(parts[0])
                        lat = float(parts[1])
                        alt = float(parts[2]) if len(parts) >= 3 else 0
                        measurement.coordinates.append((lon, lat, alt))

            measurement.raw_xml = ET.tostring(pm_elem, encoding='unicode')[:500]
            paths.append(measurement)

    except Exception:
        # Fallback to regex
        linestring_pattern = r'<LineString>.*?<coordinates>\s*([^<]+)\s*</coordinates>.*?</LineString>'
        for match in re.finditer(linestring_pattern, kml_content, re.DOTALL):
            measurement = MeasurementInfo()
            coords_text = match.group(1).strip()

            for point in coords_text.split():
                parts = point.split(',')
                if len(parts) >= 2:
                    lon = float(parts[0])
                    lat = float(parts[1])
                    alt = float(parts[2]) if len(parts) >= 3 else 0
                    measurement.coordinates.append((lon, lat, alt))

            paths.append(measurement)

    return paths


# ============================================================================
# COORDINATE UTILITIES
# ============================================================================

def coordinates_within_tolerance(
    lat1: float, lon1: float,
    lat2: float, lon2: float,
    tolerance_degrees: float = 0.01
) -> bool:
    """Check if two coordinates are within tolerance (simple rectangular check)."""
    return (abs(lat1 - lat2) <= tolerance_degrees and
            abs(lon1 - lon2) <= tolerance_degrees)


def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
    Calculate the great-circle distance between two points in meters.
    """
    import math

    R = 6371000  # Earth's radius in meters

    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)

    a = (math.sin(delta_phi/2)**2 +
         math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda/2)**2)
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))

    return R * c


# ============================================================================
# IMAGE METADATA EXTRACTION
# ============================================================================

def extract_image_metadata(filepath: str) -> ImageMetadata:
    """
    Extract metadata from an image file, including GPS coordinates.

    Google Earth Pro embeds GPS coordinates in saved images.
    """
    metadata = ImageMetadata(filepath=filepath)

    if not os.path.exists(filepath):
        return metadata

    try:
        # Method 1: Use exiftool (most reliable for GPS)
        result = subprocess.run(
            ['exiftool', '-json', '-GPS*', '-ImageWidth', '-ImageHeight',
             '-Software', '-CreateDate', filepath],
            capture_output=True,
            text=True,
            timeout=30
        )

        if result.returncode == 0:
            data = json.loads(result.stdout)
            if data:
                info = data[0]

                metadata.width = info.get('ImageWidth')
                metadata.height = info.get('ImageHeight')
                metadata.software = info.get('Software', '')
                metadata.creation_time = info.get('CreateDate')

                # Parse GPS coordinates
                gps_lat = info.get('GPSLatitude')
                gps_lon = info.get('GPSLongitude')
                gps_lat_ref = info.get('GPSLatitudeRef', 'N')
                gps_lon_ref = info.get('GPSLongitudeRef', 'E')

                if gps_lat is not None and gps_lon is not None:
                    # Handle different formats
                    if isinstance(gps_lat, str):
                        # Format: "48 deg 51' 29.88" N"
                        lat = parse_gps_coordinate(gps_lat)
                        lon = parse_gps_coordinate(gps_lon)
                    else:
                        lat = float(gps_lat)
                        lon = float(gps_lon)

                    if lat is not None and lon is not None:
                        if gps_lat_ref == 'S':
                            lat = -lat
                        if gps_lon_ref == 'W':
                            lon = -lon

                        metadata.gps_latitude = lat
                        metadata.gps_longitude = lon
                        metadata.has_gps = True

                gps_alt = info.get('GPSAltitude')
                if gps_alt is not None:
                    if isinstance(gps_alt, str):
                        # Parse "123.4 m" format
                        alt_match = re.search(r'([\d.]+)', gps_alt)
                        if alt_match:
                            metadata.gps_altitude = float(alt_match.group(1))
                    else:
                        metadata.gps_altitude = float(gps_alt)

    except Exception:
        pass

    # Fallback: Use PIL for basic info
    if metadata.width is None:
        try:
            from PIL import Image
            with Image.open(filepath) as img:
                metadata.width, metadata.height = img.size
        except Exception:
            pass

    return metadata


def parse_gps_coordinate(coord_str: str) -> Optional[float]:
    """Parse GPS coordinate from EXIF string format."""
    # Format: "48 deg 51' 29.88" N" or "48.8584"
    try:
        # Try simple float first
        return float(coord_str)
    except ValueError:
        pass

    # Try DMS format
    dms_pattern = r"(\d+)\s*(?:deg)?\s*(\d+)['\s]+(\d+\.?\d*)"
    match = re.search(dms_pattern, coord_str)
    if match:
        d, m, s = float(match.group(1)), float(match.group(2)), float(match.group(3))
        return d + m/60 + s/3600

    return None


# ============================================================================
# FILE INTEGRITY AND STATE TRACKING
# ============================================================================

def compute_file_hash(filepath: str) -> Optional[str]:
    """Compute SHA256 hash of a file."""
    try:
        with open(filepath, 'rb') as f:
            return hashlib.sha256(f.read()).hexdigest()
    except Exception:
        return None


def save_baseline_state(baseline_path: str = '/tmp/ge_baseline_state.json'):
    """
    Save baseline state of Google Earth files for later comparison.
    Call this at the START of a task.
    """
    state = {
        'timestamp': time.time(),
        'myplaces_hash': None,
        'myplaces_exists': False,
        'myplaces_content': None,
    }

    myplaces_path = GOOGLE_EARTH_STATE_DIR / 'myplaces.kml'
    if myplaces_path.exists():
        state['myplaces_exists'] = True
        state['myplaces_hash'] = compute_file_hash(str(myplaces_path))
        try:
            state['myplaces_content'] = myplaces_path.read_text()
        except Exception:
            pass

    with open(baseline_path, 'w') as f:
        json.dump(state, f)

    return state


def load_baseline_state(baseline_path: str = '/tmp/ge_baseline_state.json') -> Optional[Dict]:
    """Load previously saved baseline state."""
    try:
        with open(baseline_path, 'r') as f:
            return json.load(f)
    except Exception:
        return None


def get_new_placemarks_since_baseline(baseline_path: str = '/tmp/ge_baseline_state.json') -> List[PlacemarkInfo]:
    """
    Compare current myplaces.kml with baseline to find NEW placemarks.
    """
    baseline = load_baseline_state(baseline_path)

    myplaces_path = GOOGLE_EARTH_STATE_DIR / 'myplaces.kml'
    if not myplaces_path.exists():
        return []

    current_content = myplaces_path.read_text()
    current_placemarks = parse_placemarks_from_kml(current_content)

    if baseline is None or baseline.get('myplaces_content') is None:
        # No baseline, return all current placemarks
        return current_placemarks

    baseline_placemarks = parse_placemarks_from_kml(baseline['myplaces_content'])
    baseline_names = {pm.name.lower() for pm in baseline_placemarks if pm.name}

    # Find placemarks not in baseline
    new_placemarks = [
        pm for pm in current_placemarks
        if pm.name and pm.name.lower() not in baseline_names
    ]

    return new_placemarks


# ============================================================================
# RULER/MEASUREMENT TOOL UTILITIES
# ============================================================================

def check_ruler_dialog_open() -> bool:
    """Check if the Google Earth Ruler dialog is currently open."""
    try:
        result = subprocess.run(
            ['wmctrl', '-l'],
            capture_output=True,
            text=True,
            timeout=5
        )
        for line in result.stdout.splitlines():
            if 'Ruler' in line or 'Measure' in line:
                return True
    except Exception:
        pass
    return False


def extract_measurement_from_ruler_ocr() -> Optional[float]:
    """
    Try to OCR the ruler dialog to extract the measured distance.
    Returns distance in meters if found.
    """
    try:
        # Find ruler window
        result = subprocess.run(
            ['wmctrl', '-l'],
            capture_output=True,
            text=True,
            timeout=5
        )

        ruler_window_id = None
        for line in result.stdout.splitlines():
            if 'Ruler' in line:
                ruler_window_id = line.split()[0]
                break

        if not ruler_window_id:
            return None

        # Focus and screenshot the ruler dialog
        subprocess.run(['wmctrl', '-i', '-a', ruler_window_id], timeout=5)
        time.sleep(0.3)

        with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as tmp:
            screenshot_path = tmp.name

        # Screenshot just the ruler window
        subprocess.run([
            'import', '-window', ruler_window_id, screenshot_path
        ], timeout=10)

        # OCR it
        result = subprocess.run(
            ['tesseract', screenshot_path, 'stdout', '-l', 'eng'],
            capture_output=True,
            text=True,
            timeout=30
        )

        ocr_text = result.stdout
        os.unlink(screenshot_path)

        # Parse distance from OCR
        # Formats: "8.54 km", "8.54 kilometers", "5.31 mi", "5.31 miles"
        km_pattern = r'(\d+\.?\d*)\s*(?:km|kilometers)'
        mi_pattern = r'(\d+\.?\d*)\s*(?:mi|miles)'
        m_pattern = r'(\d+\.?\d*)\s*(?:m|meters)(?!\w)'  # meters but not miles

        km_match = re.search(km_pattern, ocr_text.lower())
        if km_match:
            return float(km_match.group(1)) * 1000

        mi_match = re.search(mi_pattern, ocr_text.lower())
        if mi_match:
            return float(mi_match.group(1)) * 1609.34

        m_match = re.search(m_pattern, ocr_text.lower())
        if m_match:
            return float(m_match.group(1))

    except Exception:
        pass

    return None


def get_measurement_paths_from_kml() -> List[MeasurementInfo]:
    """Get all measurement paths from myplaces.kml."""
    myplaces_path = GOOGLE_EARTH_STATE_DIR / 'myplaces.kml'
    if not myplaces_path.exists():
        return []

    content = myplaces_path.read_text()
    return parse_paths_from_kml(content)


# ============================================================================
# SCREENSHOT UTILITIES
# ============================================================================

def find_recent_images(
    search_paths: List[str] = None,
    max_age_seconds: int = 300,
    min_width: int = 800,
    min_height: int = 600
) -> List[ImageMetadata]:
    """
    Find recently created/modified image files.
    """
    if search_paths is None:
        search_paths = [
            '/home/ga/Desktop/*.jpg',
            '/home/ga/Desktop/*.jpeg',
            '/home/ga/Desktop/*.png',
            '/home/ga/Pictures/*.jpg',
            '/home/ga/Pictures/*.jpeg',
            '/home/ga/Pictures/*.png',
            '/home/ga/*.jpg',
            '/home/ga/*.jpeg',
            '/home/ga/*.png',
        ]

    import glob

    recent_images = []
    current_time = time.time()

    for pattern in search_paths:
        for filepath in glob.glob(pattern):
            try:
                mtime = os.path.getmtime(filepath)
                if (current_time - mtime) > max_age_seconds:
                    continue

                metadata = extract_image_metadata(filepath)

                # Filter by size
                if (metadata.width and metadata.height and
                    metadata.width >= min_width and metadata.height >= min_height):
                    recent_images.append(metadata)

            except Exception:
                continue

    return recent_images


# ============================================================================
# LEGACY COMPATIBILITY (for any code that might use old functions)
# ============================================================================

def get_window_title() -> Optional[str]:
    """Legacy function - get active window title."""
    try:
        result = subprocess.run(
            ['xdotool', 'getactivewindow', 'getwindowname'],
            capture_output=True,
            text=True,
            timeout=5
        )
        return result.stdout.strip()
    except Exception:
        return None


def take_screenshot(output_path: str) -> bool:
    """Legacy function - take a screenshot."""
    try:
        result = subprocess.run(
            ['scrot', output_path],
            capture_output=True,
            timeout=10
        )
        return result.returncode == 0 and os.path.exists(output_path)
    except Exception:
        return False


def get_googleearth_state_dir(username: str = 'ga') -> Path:
    """Legacy function - get Google Earth state directory."""
    return Path(f'/home/{username}/.googleearth')


def check_file_exists(filepath: str) -> bool:
    """Legacy function - check if file exists."""
    return os.path.exists(filepath)


def check_file_modified_recently(filepath: str, seconds: int = 300) -> bool:
    """Legacy function - check if file was recently modified."""
    try:
        mtime = os.path.getmtime(filepath)
        return (time.time() - mtime) < seconds
    except Exception:
        return False


def get_image_dimensions(image_path: str) -> Optional[Tuple[int, int]]:
    """Legacy function - get image dimensions."""
    try:
        from PIL import Image
        with Image.open(image_path) as img:
            return img.size
    except Exception:
        return None
