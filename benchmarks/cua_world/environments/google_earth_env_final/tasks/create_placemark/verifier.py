"""
Verifier for create_placemark task.

Task: "Create and save a placemark at a specific location in Google Earth.
       Navigate to the Golden Gate Bridge in San Francisco and create a
       placemark named 'Golden Gate Bridge' at that location."

What this actually means:
- Agent should navigate to Golden Gate Bridge area
- Agent should create a NEW placemark (Add → Placemark or Ctrl+Shift+P)
- Placemark should be named "Golden Gate Bridge"
- Placemark coordinates should be at/near the bridge

Verification Strategy:
- Load baseline myplaces.kml saved by setup script
- Compare current myplaces.kml to find NEW placemarks
- Check if new placemark has correct name and coordinates
- VLM: Verify view shows San Francisco / Golden Gate Bridge area
"""

import os
import sys
import json
import logging
import re
from pathlib import Path
from typing import Dict, Any, List, Optional, Tuple
import xml.etree.ElementTree as ET
from math import radians, sin, cos, sqrt, atan2

from gym_anything.vlm import get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# =============================================================================
# CONSTANTS
# =============================================================================

TARGET_NAME = "Golden Gate Bridge"
TARGET_LAT = 37.8199
TARGET_LON = -122.4783
COORDINATE_TOLERANCE_KM = 2.0  # Accept placemarks within 2km of bridge center

BASELINE_FILE = "/tmp/ge_baseline_state.json"
MYPLACES_FILE = "/home/ga/.googleearth/myplaces.kml"

KML_NS = {
    'kml': 'http://www.opengis.net/kml/2.2',
    'gx': 'http://www.google.com/kml/ext/2.2',
}


# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate distance between two coordinates in kilometers."""
    R = 6371  # Earth's radius in km
    lat1, lon1, lat2, lon2 = map(radians, [lat1, lon1, lat2, lon2])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = sin(dlat/2)**2 + cos(lat1) * cos(lat2) * sin(dlon/2)**2
    c = 2 * atan2(sqrt(a), sqrt(1-a))
    return R * c


def parse_placemarks_from_kml(kml_content: str) -> List[Dict[str, Any]]:
    """
    Extract all placemarks from KML content.
    Returns list of dicts with 'name', 'lat', 'lon'.
    """
    placemarks = []

    if not kml_content:
        return placemarks

    try:
        root = ET.fromstring(kml_content)

        # Find all Placemark elements (with or without namespace)
        for ns_prefix in ['kml:', '']:
            for pm in root.iter(f'{{{KML_NS.get("kml", "")}}}Placemark' if ns_prefix else 'Placemark'):
                placemark_info = {'name': None, 'lat': None, 'lon': None, 'raw': ET.tostring(pm, encoding='unicode')}

                # Get name
                name_elem = pm.find(f'{ns_prefix}name', KML_NS) if ns_prefix else pm.find('name')
                if name_elem is not None and name_elem.text:
                    placemark_info['name'] = name_elem.text.strip()

                # Get coordinates from Point/coordinates
                coords_elem = None
                point = pm.find(f'{ns_prefix}Point', KML_NS) if ns_prefix else pm.find('Point')
                if point is not None:
                    coords_elem = point.find(f'{ns_prefix}coordinates', KML_NS) if ns_prefix else point.find('coordinates')

                # Also try direct coordinates element
                if coords_elem is None:
                    coords_elem = pm.find(f'.//{ns_prefix}coordinates', KML_NS) if ns_prefix else pm.find('.//coordinates')

                if coords_elem is not None and coords_elem.text:
                    coords_text = coords_elem.text.strip()
                    # Format: lon,lat,alt or lon,lat
                    parts = coords_text.split(',')
                    if len(parts) >= 2:
                        try:
                            placemark_info['lon'] = float(parts[0])
                            placemark_info['lat'] = float(parts[1])
                        except ValueError:
                            pass

                placemarks.append(placemark_info)

        # Also try without namespace if we got no results
        if not placemarks:
            for pm in root.iter():
                if pm.tag.endswith('Placemark') or pm.tag == 'Placemark':
                    placemark_info = {'name': None, 'lat': None, 'lon': None}

                    for child in pm:
                        tag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                        if tag == 'name' and child.text:
                            placemark_info['name'] = child.text.strip()

                    for coords in pm.iter():
                        tag = coords.tag.split('}')[-1] if '}' in coords.tag else coords.tag
                        if tag == 'coordinates' and coords.text:
                            parts = coords.text.strip().split(',')
                            if len(parts) >= 2:
                                try:
                                    placemark_info['lon'] = float(parts[0])
                                    placemark_info['lat'] = float(parts[1])
                                except ValueError:
                                    pass

                    placemarks.append(placemark_info)

    except ET.ParseError as e:
        logger.warning(f"Failed to parse KML: {e}")

    return placemarks


def find_new_placemarks(baseline_content: Optional[str], current_content: str) -> List[Dict[str, Any]]:
    """
    Compare baseline and current KML to find NEW placemarks.
    Returns list of placemarks that exist in current but not in baseline.
    """
    baseline_pms = parse_placemarks_from_kml(baseline_content) if baseline_content else []
    current_pms = parse_placemarks_from_kml(current_content)

    # Create fingerprints for baseline placemarks (name + approximate location)
    baseline_fingerprints = set()
    for pm in baseline_pms:
        # Use name + rounded coordinates as fingerprint
        lat = round(pm.get('lat', 0) or 0, 4)
        lon = round(pm.get('lon', 0) or 0, 4)
        name = (pm.get('name') or '').lower().strip()
        baseline_fingerprints.add(f"{name}|{lat}|{lon}")

    # Find placemarks in current that aren't in baseline
    new_pms = []
    for pm in current_pms:
        lat = round(pm.get('lat', 0) or 0, 4)
        lon = round(pm.get('lon', 0) or 0, 4)
        name = (pm.get('name') or '').lower().strip()
        fingerprint = f"{name}|{lat}|{lon}"

        if fingerprint not in baseline_fingerprints:
            new_pms.append(pm)

    return new_pms


def is_golden_gate_placemark(pm: Dict[str, Any]) -> Tuple[bool, str]:
    """
    Check if a placemark is the Golden Gate Bridge placemark.
    Returns (is_match, reason).
    """
    name = pm.get('name', '') or ''
    lat = pm.get('lat')
    lon = pm.get('lon')

    # Check name (flexible matching)
    name_lower = name.lower()
    name_matches = (
        'golden gate' in name_lower or
        ('golden' in name_lower and 'gate' in name_lower) or
        'gg bridge' in name_lower
    )

    # Check coordinates
    coords_match = False
    distance_km = None
    if lat is not None and lon is not None:
        distance_km = haversine_distance(lat, lon, TARGET_LAT, TARGET_LON)
        coords_match = distance_km <= COORDINATE_TOLERANCE_KM

    if name_matches and coords_match:
        return True, f"Name matches, coordinates {distance_km:.1f}km from target"
    elif name_matches and lat is None:
        return False, "Name matches but no coordinates"
    elif name_matches:
        return False, f"Name matches but {distance_km:.1f}km from target"
    elif coords_match:
        return False, f"Coordinates match but name is '{name}'"
    else:
        return False, f"Name '{name}' doesn't match, coords don't match"


# =============================================================================
# VLM PROMPT
# =============================================================================

VERIFICATION_PROMPT = """You are verifying if a computer agent completed a task in Google Earth.

TASK: Navigate to the Golden Gate Bridge in San Francisco and create a placemark there.

Look at this screenshot and determine:

1. Is this Google Earth (satellite/aerial imagery application)?

2. Does this show the San Francisco / Golden Gate Bridge area? Look for:
   - San Francisco Bay Area (recognizable bay shape)
   - The Golden Gate strait (narrow water channel connecting bay to Pacific)
   - Urban areas of San Francisco or Marin County
   - Any view that includes or is near the Golden Gate Bridge location

3. Is there any evidence of placemark creation?
   - A placemark pin/marker icon visible
   - A placemark dialog or properties panel open
   - A label or name visible near a marker

Note: The task doesn't require a specific zoom level. A wide view showing the SF Bay Area OR a close-up of the bridge area are both acceptable.

Respond in JSON format:
{
    "is_google_earth": true/false,
    "shows_sf_area": true/false,
    "golden_gate_area_visible": true/false,
    "placemark_evidence": true/false,
    "placemark_details": "what placemark evidence is visible, or null",
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you see"
}
"""


# =============================================================================
# MAIN VERIFICATION FUNCTION
# =============================================================================

def check_placemark(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that a placemark named "Golden Gate Bridge" was created at the
    Golden Gate Bridge location.

    Uses hybrid verification:
    - Programmatic: Compare myplaces.kml to baseline to find new placemarks
    - VLM: Verify view shows San Francisco / Golden Gate area

    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info
        task_info: Task info with task_id

    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    feedback_parts = []
    result_details = {}

    # =========================================================================
    # PROGRAMMATIC CHECK: Compare KML to baseline
    # =========================================================================

    # Load baseline
    baseline_content = None
    if os.path.exists(BASELINE_FILE):
        try:
            with open(BASELINE_FILE, 'r') as f:
                baseline_data = json.load(f)
            baseline_content = baseline_data.get('myplaces_content')
            result_details['baseline_loaded'] = True
            result_details['baseline_had_myplaces'] = baseline_data.get('myplaces_exists', False)
        except Exception as e:
            logger.warning(f"Failed to load baseline: {e}")
            result_details['baseline_loaded'] = False
    else:
        result_details['baseline_loaded'] = False
        feedback_parts.append("⚠️ No baseline state available")

    # Load current myplaces.kml
    current_content = None
    if os.path.exists(MYPLACES_FILE):
        try:
            with open(MYPLACES_FILE, 'r') as f:
                current_content = f.read()
            result_details['current_myplaces_exists'] = True
        except Exception as e:
            logger.warning(f"Failed to read current myplaces.kml: {e}")
            result_details['current_myplaces_exists'] = False
    else:
        result_details['current_myplaces_exists'] = False

    # Find new placemarks
    kml_passed = False
    kml_partial = False
    new_pms = []

    if current_content:
        new_pms = find_new_placemarks(baseline_content, current_content)
        result_details['new_placemarks_count'] = len(new_pms)
        result_details['new_placemarks'] = [
            {'name': pm.get('name'), 'lat': pm.get('lat'), 'lon': pm.get('lon')}
            for pm in new_pms
        ]

        if new_pms:
            # Check each new placemark
            matching_pm = None
            for pm in new_pms:
                is_match, reason = is_golden_gate_placemark(pm)
                if is_match:
                    matching_pm = pm
                    break

            if matching_pm:
                kml_passed = True
                name = matching_pm.get('name', '(unnamed)')
                lat = matching_pm.get('lat')
                lon = matching_pm.get('lon')
                if lat and lon:
                    dist = haversine_distance(lat, lon, TARGET_LAT, TARGET_LON)
                    feedback_parts.append(f"✅ New placemark '{name}' at Golden Gate ({dist:.1f}km from center)")
                else:
                    feedback_parts.append(f"✅ New placemark '{name}' created")
            else:
                # New placemarks exist but don't match criteria
                kml_partial = True
                pm_names = [pm.get('name', '(unnamed)') for pm in new_pms[:3]]
                feedback_parts.append(f"⚠️ New placemarks found but don't match: {pm_names}")
        else:
            feedback_parts.append("❌ No new placemarks created")
    else:
        feedback_parts.append("❌ No myplaces.kml found")

    # =========================================================================
    # VLM CHECK: Verify view shows Golden Gate area
    # =========================================================================

    vlm_passed = False
    vlm_partial = False

    query_vlm = env_info.get('query_vlm')
    final_screenshot = get_final_screenshot(traj)
    result_details['final_screenshot'] = final_screenshot

    if query_vlm and final_screenshot:
        vlm_result = query_vlm(
            prompt=VERIFICATION_PROMPT,
            image=final_screenshot,
        )
        result_details['vlm_result'] = vlm_result

        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})

            is_google_earth = parsed.get("is_google_earth", False)
            shows_sf = parsed.get("shows_sf_area", False)
            gg_visible = parsed.get("golden_gate_area_visible", False)
            placemark_evidence = parsed.get("placemark_evidence", False)
            confidence = parsed.get("confidence", "low")
            reasoning = parsed.get("reasoning", "")

            if is_google_earth and (shows_sf or gg_visible):
                if placemark_evidence:
                    vlm_passed = True
                    details = parsed.get("placemark_details", "")
                    feedback_parts.append(f"✅ SF/Golden Gate area visible with placemark ({confidence})")
                else:
                    vlm_partial = True
                    feedback_parts.append(f"✅ SF/Golden Gate area visible ({confidence})")
            elif is_google_earth:
                feedback_parts.append(f"❌ Google Earth visible but not SF area ({confidence})")
            else:
                feedback_parts.append("❌ Google Earth not confirmed by VLM")

            if reasoning:
                result_details['vlm_reasoning'] = reasoning
        else:
            feedback_parts.append(f"⚠️ VLM check failed: {vlm_result.get('error', 'Unknown')}")
    else:
        feedback_parts.append("⚠️ No screenshot for VLM verification")

    # =========================================================================
    # CALCULATE FINAL RESULT
    # =========================================================================

    # Scoring:
    # - KML check passed (correct placemark): 60 points
    # - KML partial (placemarks but wrong): 20 points
    # - VLM check passed (area + placemark visible): 40 points
    # - VLM partial (area visible): 20 points

    score = 0
    if kml_passed:
        score += 60
    elif kml_partial:
        score += 20

    if vlm_passed:
        score += 40
    elif vlm_partial:
        score += 20

    # Pass if:
    # - KML shows correct placemark created (primary criterion)
    # - OR high confidence VLM shows placemark at right location
    passed = kml_passed or (vlm_passed and score >= 60)

    # Summary
    if passed:
        feedback_parts.append(f"🎉 Successfully created placemark at {TARGET_NAME}!")
    else:
        feedback_parts.append("❌ Placemark creation not verified")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result_details,
    }
