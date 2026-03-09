#!/usr/bin/env python3
"""
Verifier for Solar Roof Assessment task.

VERIFICATION STRATEGY (Multi-Signal):
1. Placemark with correct name exists (10 points)
2. Placemark created/modified during task - anti-gaming (15 points)
3. Placemark coordinates near IKEA location (15 points)
4. Area measurement documented in description (20 points)
5. Orientation documented in description (15 points)
6. VLM trajectory: Navigation to IKEA visible (10 points)
7. VLM trajectory: Polygon ruler tool usage (10 points)
8. Professional documentation format (5 points)

Pass threshold: 70 points with placemark created and area documented.
"""

import json
import tempfile
import os
import re
import logging
from typing import Dict, Any, Optional, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Target coordinates
TARGET_LAT = 37.4683
TARGET_LON = -122.1325
COORD_TOLERANCE = 0.01  # degrees (~1km)

# Expected area ranges
AREA_RANGES = {
    'sq_ft': (280000, 420000),
    'sqft': (280000, 420000),
    'square feet': (280000, 420000),
    'sq_m': (26000, 39000),
    'sqm': (26000, 39000),
    'square meters': (26000, 39000),
    'acres': (6.4, 9.6),
}


# =============================================================================
# VLM Prompts
# =============================================================================

TRAJECTORY_NAVIGATION_PROMPT = """You are analyzing a sequence of screenshots from an agent performing a task in Google Earth Pro.

The screenshots are in chronological order (earliest to latest).

TASK: Navigate to IKEA East Palo Alto and measure the roof using polygon ruler tool.

Assess the trajectory for evidence of:
1. NAVIGATION_TO_IKEA: Did the agent navigate to a location showing an IKEA store or the East Palo Alto area?
   - Look for: Blue IKEA building, "IKEA" text in search/view, commercial building with parking lot
2. POLYGON_RULER_VISIBLE: Is there evidence of using the polygon ruler tool?
   - Look for: Ruler dialog window, polygon overlay on building, measurement display
3. MEASUREMENT_PERFORMED: Did the agent appear to measure something?
   - Look for: Yellow/white polygon lines on a roof, area measurement numbers visible
4. PLACEMARK_DIALOG: Did the agent open a placemark creation dialog?
   - Look for: "New Placemark" or "Add Placemark" dialog with name and description fields

Respond in JSON format:
{
    "navigation_to_ikea": true/false,
    "polygon_ruler_visible": true/false,
    "measurement_performed": true/false,
    "placemark_dialog_visible": true/false,
    "ikea_building_visible": true/false,
    "google_earth_interface_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you observe across the trajectory"
}
"""

FINAL_STATE_PROMPT = """You are verifying the final state of a Google Earth Pro task.

TASK: The agent should have navigated to IKEA East Palo Alto and created a solar assessment placemark.

Look at this final screenshot and determine:
1. Is this Google Earth Pro showing a map/satellite view?
2. Is there evidence of an IKEA store or East Palo Alto area visible?
3. Are there any placemark pins visible on the map?
4. Is there a polygon measurement overlay visible on a building?
5. Is there any dialog or sidebar showing placemark details?

Respond in JSON format:
{
    "is_google_earth": true/false,
    "shows_commercial_area": true/false,
    "placemark_visible": true/false,
    "polygon_overlay_visible": true/false,
    "measurement_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief description of what you see"
}
"""


# =============================================================================
# Helper Functions
# =============================================================================

def check_coordinates_in_range(lat: Optional[float], lon: Optional[float]) -> bool:
    """Check if coordinates are within tolerance of target IKEA location."""
    if lat is None or lon is None:
        return False
    lat_diff = abs(lat - TARGET_LAT)
    lon_diff = abs(lon - TARGET_LON)
    return lat_diff <= COORD_TOLERANCE and lon_diff <= COORD_TOLERANCE


def check_area_in_valid_range(area_value: Optional[float], area_unit: Optional[str]) -> Tuple[bool, bool]:
    """
    Check if area value is within expected range for IKEA roof.
    Returns: (has_area, area_valid)
    """
    if area_value is None:
        return False, False
    
    if area_unit is None:
        # Try to guess based on value magnitude
        if 200000 <= area_value <= 500000:
            # Likely sq ft
            return True, True
        elif 20000 <= area_value <= 50000:
            # Likely sq m
            return True, True
        elif 5 <= area_value <= 15:
            # Likely acres
            return True, True
        return True, False
    
    unit_lower = area_unit.lower().strip()
    
    # Normalize unit names
    unit_mapping = {
        'sq ft': 'sq_ft', 'sq. ft': 'sq_ft', 'sqft': 'sq_ft',
        'square feet': 'sq_ft', 'square foot': 'sq_ft',
        'sq m': 'sq_m', 'sq. m': 'sq_m', 'sqm': 'sq_m',
        'square meters': 'sq_m', 'square meter': 'sq_m',
        'acre': 'acres', 'acres': 'acres',
    }
    
    normalized_unit = unit_mapping.get(unit_lower, unit_lower)
    
    if normalized_unit in AREA_RANGES:
        min_val, max_val = AREA_RANGES[normalized_unit]
        return True, min_val <= area_value <= max_val
    
    return True, False


def extract_area_from_text(text: str) -> Tuple[Optional[float], Optional[str]]:
    """Extract area measurement from text."""
    if not text:
        return None, None
    
    text_lower = text.lower()
    
    patterns = [
        (r'([\d,]+(?:\.\d+)?)\s*(sq\.?\s*ft|square\s*feet|sqft)', 'sq_ft'),
        (r'([\d,]+(?:\.\d+)?)\s*(sq\.?\s*m|square\s*meters?|sqm)', 'sq_m'),
        (r'([\d,]+(?:\.\d+)?)\s*(acres?)', 'acres'),
        (r'area[:\s]*([\d,]+(?:\.\d+)?)', None),  # Generic area mention
    ]
    
    for pattern, default_unit in patterns:
        match = re.search(pattern, text_lower)
        if match:
            try:
                value_str = match.group(1).replace(',', '')
                value = float(value_str)
                unit = match.group(2) if len(match.groups()) > 1 else default_unit
                return value, unit
            except (ValueError, IndexError):
                continue
    
    return None, None


def check_orientation_in_text(text: str) -> bool:
    """Check if text contains orientation information."""
    if not text:
        return False
    
    text_lower = text.lower()
    
    patterns = [
        r'\b(north|south|east|west)\b',
        r'\b(n|s|e|w)\b(?![a-z])',  # Single letters not part of words
        r'\b(nw|ne|sw|se)\b',
        r'\b(n-s|e-w|north-south|east-west)\b',
        r'\b(northwest|northeast|southwest|southeast)\b',
        r'orientation',
        r'aligned',
        r'facing',
        r'azimuth',
    ]
    
    for pattern in patterns:
        if re.search(pattern, text_lower):
            return True
    
    return False


def sample_trajectory_frames(traj: Dict[str, Any], n: int = 5) -> list:
    """Sample n frames evenly from trajectory."""
    frames = traj.get('frames', [])
    if not frames:
        return []
    
    if len(frames) <= n:
        return frames
    
    # Sample evenly across trajectory
    indices = [int(i * (len(frames) - 1) / (n - 1)) for i in range(n)]
    return [frames[i] for i in indices]


def get_final_screenshot(traj: Dict[str, Any]) -> Optional[str]:
    """Get the final screenshot from trajectory."""
    frames = traj.get('frames', [])
    if frames:
        return frames[-1]
    return None


# =============================================================================
# Main Verification Function
# =============================================================================

def verify_solar_roof_assessment(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the Solar Roof Assessment task.
    
    Uses multiple independent signals:
    1. KML file analysis (programmatic)
    2. Timestamp verification (anti-gaming)
    3. VLM trajectory analysis (process verification)
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available"
        }
    
    metadata = task_info.get('metadata', {})
    feedback_parts = []
    details = {}
    score = 0
    max_score = 100
    
    # =========================================================================
    # STEP 1: Copy result files from container
    # =========================================================================
    
    # Copy main result JSON
    result_data = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        details['result_data'] = result_data
    except Exception as e:
        logger.warning(f"Could not read task result: {e}")
        details['result_error'] = str(e)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # Copy placemark details
    placemark_data = {}
    temp_placemark = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/placemark_search.json", temp_placemark.name)
        with open(temp_placemark.name, 'r') as f:
            placemark_data = json.load(f)
        details['placemark_data'] = placemark_data
    except Exception as e:
        logger.warning(f"Could not read placemark details: {e}")
    finally:
        if os.path.exists(temp_placemark.name):
            os.unlink(temp_placemark.name)
    
    # =========================================================================
    # CRITERION 1: Placemark with correct name exists (10 points)
    # =========================================================================
    
    placemark_found = placemark_data.get('found', False)
    placemark_name = placemark_data.get('name', '')
    has_ikea = placemark_data.get('has_ikea', False)
    has_solar = placemark_data.get('has_solar', False)
    
    if placemark_found and has_ikea and has_solar:
        score += 10
        feedback_parts.append(f"✅ Placemark created: '{placemark_name}'")
    elif placemark_found:
        score += 5
        feedback_parts.append(f"⚠️ Placemark found but missing keywords: '{placemark_name}'")
    else:
        feedback_parts.append("❌ No matching placemark found (needs 'IKEA' and 'Solar' in name)")
    
    details['placemark_found'] = placemark_found
    details['placemark_name'] = placemark_name
    
    # =========================================================================
    # CRITERION 2: File modified during task - anti-gaming (15 points)
    # =========================================================================
    
    myplaces_modified = result_data.get('myplaces_modified_during_task', False)
    new_placemarks = result_data.get('new_placemarks_created', 0)
    task_start = result_data.get('task_start', 0)
    myplaces_mtime = result_data.get('myplaces_mtime', 0)
    
    if myplaces_modified and new_placemarks > 0:
        score += 15
        feedback_parts.append(f"✅ Placemark created during task ({new_placemarks} new)")
    elif myplaces_modified:
        score += 10
        feedback_parts.append("⚠️ myplaces.kml modified but no new placemarks detected")
    elif myplaces_mtime > 0 and task_start > 0:
        feedback_parts.append("❌ myplaces.kml not modified during task (possible pre-existing)")
    else:
        feedback_parts.append("❌ No myplaces.kml modification detected")
    
    details['file_modified_during_task'] = myplaces_modified
    details['new_placemarks'] = new_placemarks
    
    # =========================================================================
    # CRITERION 3: Placemark coordinates near IKEA (15 points)
    # =========================================================================
    
    placemark_lat = placemark_data.get('latitude')
    placemark_lon = placemark_data.get('longitude')
    coords_valid = check_coordinates_in_range(placemark_lat, placemark_lon)
    
    if coords_valid:
        score += 15
        feedback_parts.append(f"✅ Location correct ({placemark_lat:.4f}, {placemark_lon:.4f})")
    elif placemark_lat is not None and placemark_lon is not None:
        score += 5
        feedback_parts.append(f"⚠️ Location detected but not near IKEA ({placemark_lat:.4f}, {placemark_lon:.4f})")
    else:
        feedback_parts.append("❌ No valid coordinates in placemark")
    
    details['coordinates_valid'] = coords_valid
    details['placemark_lat'] = placemark_lat
    details['placemark_lon'] = placemark_lon
    
    # =========================================================================
    # CRITERION 4: Area measurement documented (20 points)
    # =========================================================================
    
    has_area = placemark_data.get('has_area', False)
    area_value = placemark_data.get('area_value')
    area_unit = placemark_data.get('area_unit')
    
    if has_area and area_value is not None:
        _, area_valid = check_area_in_valid_range(area_value, area_unit)
        if area_valid:
            score += 20
            feedback_parts.append(f"✅ Area documented and valid: {area_value:,.0f} {area_unit or 'units'}")
        else:
            score += 12
            feedback_parts.append(f"⚠️ Area documented but outside expected range: {area_value:,.0f} {area_unit or 'units'}")
    else:
        feedback_parts.append("❌ No area measurement found in description")
    
    details['area_documented'] = has_area
    details['area_value'] = area_value
    details['area_unit'] = area_unit
    
    # =========================================================================
    # CRITERION 5: Orientation documented (15 points)
    # =========================================================================
    
    has_orientation = placemark_data.get('has_orientation', False)
    
    if has_orientation:
        score += 15
        feedback_parts.append("✅ Orientation documented")
    else:
        feedback_parts.append("❌ No orientation information in description")
    
    details['orientation_documented'] = has_orientation
    
    # =========================================================================
    # CRITERION 6 & 7: VLM Trajectory Verification (20 points total)
    # =========================================================================
    
    vlm_navigation_score = 0
    vlm_tool_score = 0
    
    if query_vlm:
        # Sample trajectory frames
        trajectory_frames = sample_trajectory_frames(traj, n=5)
        
        if trajectory_frames:
            try:
                vlm_result = query_vlm(
                    prompt=TRAJECTORY_NAVIGATION_PROMPT,
                    images=trajectory_frames
                )
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_trajectory_result'] = parsed
                    
                    # Navigation verification (10 points)
                    if parsed.get('navigation_to_ikea') or parsed.get('ikea_building_visible'):
                        vlm_navigation_score = 10
                        feedback_parts.append("✅ VLM: Navigation to IKEA area confirmed")
                    elif parsed.get('google_earth_interface_visible'):
                        vlm_navigation_score = 3
                        feedback_parts.append("⚠️ VLM: Google Earth visible but IKEA not confirmed")
                    else:
                        feedback_parts.append("❌ VLM: Could not confirm navigation to IKEA")
                    
                    # Polygon tool verification (10 points)
                    if parsed.get('polygon_ruler_visible') or parsed.get('measurement_performed'):
                        vlm_tool_score = 10
                        feedback_parts.append("✅ VLM: Polygon measurement tool usage detected")
                    elif parsed.get('placemark_dialog_visible'):
                        vlm_tool_score = 5
                        feedback_parts.append("⚠️ VLM: Placemark dialog visible but no polygon tool")
                    else:
                        feedback_parts.append("❌ VLM: No polygon tool usage detected")
                else:
                    feedback_parts.append(f"⚠️ VLM trajectory query failed: {vlm_result.get('error', 'unknown')}")
                    
            except Exception as e:
                logger.warning(f"VLM trajectory verification failed: {e}")
                feedback_parts.append(f"⚠️ VLM verification error: {str(e)}")
        else:
            feedback_parts.append("⚠️ No trajectory frames available for VLM verification")
    else:
        feedback_parts.append("⚠️ VLM not available for trajectory verification")
    
    score += vlm_navigation_score + vlm_tool_score
    details['vlm_navigation_score'] = vlm_navigation_score
    details['vlm_tool_score'] = vlm_tool_score
    
    # =========================================================================
    # CRITERION 8: Professional documentation format (5 points)
    # =========================================================================
    
    description = placemark_data.get('description', '')
    has_solar_mention = 'solar' in description.lower() if description else False
    description_length = len(description) if description else 0
    
    if has_solar_mention and description_length > 50:
        score += 5
        feedback_parts.append("✅ Professional documentation with solar assessment context")
    elif description_length > 30:
        score += 2
        feedback_parts.append("⚠️ Description present but minimal")
    else:
        feedback_parts.append("❌ Description missing or too brief")
    
    details['description_length'] = description_length
    details['has_solar_mention'] = has_solar_mention
    
    # =========================================================================
    # Calculate final result
    # =========================================================================
    
    # Key criteria for passing
    key_criteria_met = (
        placemark_found and
        (myplaces_modified or new_placemarks > 0) and
        has_area
    )
    
    passed = score >= 70 and key_criteria_met
    
    # Summary
    feedback_parts.insert(0, f"Score: {score}/{max_score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }