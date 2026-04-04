#!/usr/bin/env python3
"""
Verifier for lat_landfall_marking task.

Task: Navigate along the 45°N latitude line and mark where it first crosses
land on North America's Atlantic coast (Nova Scotia).

Verification Strategy:
1. Programmatic: Parse KML for placemark with correct name, coordinates, description
2. VLM Trajectory: Verify agent enabled grid, navigated to Nova Scotia, created placemark
3. Anti-gaming: Check timestamps and new placemark creation

Scoring:
- Placemark exists with correct name pattern: 10 pts
- Latitude within ±0.005° of 45.000°N: 25 pts  
- Longitude in valid Nova Scotia range: 20 pts
- Description documents longitude: 10 pts
- Navigation to correct region: 15 pts
- Coastal positioning (not inland/offshore): 10 pts
- VLM trajectory verification (grid, workflow): 10 pts

Total: 100 pts
Pass threshold: 70 pts with latitude accuracy met
"""

import json
import tempfile
import os
import re
import logging
from typing import Dict, Any, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ================================================================
# CONSTANTS
# ================================================================

TARGET_LATITUDE = 45.0
LATITUDE_TOLERANCE = 0.005
LATITUDE_PARTIAL_TOLERANCE = 0.01
LATITUDE_MIN_TOLERANCE = 0.05

LONGITUDE_MIN = -64.5
LONGITUDE_MAX = -63.0
OPTIMAL_LONGITUDE_MIN = -64.0
OPTIMAL_LONGITUDE_MAX = -63.3

REGION_LONGITUDE_MIN = -70
REGION_LONGITUDE_MAX = -60
REGION_LATITUDE_MIN = 43
REGION_LATITUDE_MAX = 47


# ================================================================
# VLM PROMPTS
# ================================================================

TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing a sequence of screenshots showing an agent working in Google Earth to mark a latitude landfall point.

The task is to:
1. Enable the lat/long grid overlay
2. Navigate to where 45°N latitude crosses the Nova Scotia coast
3. Create a placemark at the landfall point

Looking at these screenshots (in chronological order), assess:

1. GRID_VISIBLE: At any point, is a latitude/longitude grid overlay visible on the map?
2. NOVA_SCOTIA_VISIBLE: Does any screenshot show the Nova Scotia or Atlantic Canada coastline?
3. PLACEMARK_CREATION: Is there evidence of placemark creation (dialog box, pin being placed)?
4. WORKFLOW_PROGRESSION: Do the screenshots show meaningful progression through the task?
5. COASTAL_NAVIGATION: Is there navigation to a coastal area around 45°N?

Respond in JSON format:
{
    "grid_visible": true/false,
    "nova_scotia_visible": true/false,
    "placemark_creation_visible": true/false,
    "workflow_progression": true/false,
    "coastal_navigation": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see across the frames"
}
"""

FINAL_STATE_PROMPT = """You are verifying the final state of a Google Earth task to mark a latitude landfall point.

The agent should have:
1. Navigated to Nova Scotia's Atlantic coast
2. Created a placemark where 45°N latitude meets land
3. The placemark should be visible on the coastline

Look at this final screenshot and determine:
1. Is this Google Earth with satellite/map imagery?
2. Is the view showing a coastline (land meeting water)?
3. Is there a placemark marker visible?
4. Does this appear to be the Nova Scotia/Atlantic Canada region?
5. Is there a lat/long grid overlay visible?

Respond in JSON format:
{
    "is_google_earth": true/false,
    "coastline_visible": true/false,
    "placemark_visible": true/false,
    "appears_nova_scotia": true/false,
    "grid_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""


# ================================================================
# HELPER FUNCTIONS
# ================================================================

def verify_placemark_name(name: str) -> Tuple[bool, int]:
    """Check if placemark name matches expected pattern."""
    if not name:
        return False, 0
    
    name_lower = name.lower()
    has_45n = any(x in name_lower for x in ['45n', '45°n', '45 n', '45-n'])
    has_landfall = 'landfall' in name_lower
    
    if has_45n and has_landfall:
        return True, 10
    elif has_45n or has_landfall:
        return False, 5  # Partial credit
    return False, 0


def verify_latitude(lat: float) -> Tuple[bool, int]:
    """Check if latitude is within tolerance of 45.000°N."""
    if lat is None:
        return False, 0
    
    try:
        lat = float(lat)
    except (ValueError, TypeError):
        return False, 0
    
    diff = abs(lat - TARGET_LATITUDE)
    
    if diff <= LATITUDE_TOLERANCE:
        return True, 25  # Full points
    elif diff <= LATITUDE_PARTIAL_TOLERANCE:
        return True, 20  # Partial credit
    elif diff <= LATITUDE_MIN_TOLERANCE:
        return True, 10  # Minimal credit
    return False, 0


def verify_longitude(lon: float) -> Tuple[bool, int]:
    """Check if longitude is in valid Nova Scotia coastal range."""
    if lon is None:
        return False, 0
    
    try:
        lon = float(lon)
    except (ValueError, TypeError):
        return False, 0
    
    # Valid range for Nova Scotia coast at 45N
    if LONGITUDE_MIN <= lon <= LONGITUDE_MAX:
        return True, 20
    # Extended range (partial credit)
    elif LONGITUDE_MIN - 0.5 <= lon <= LONGITUDE_MAX + 0.5:
        return True, 10
    return False, 0


def verify_coastal_position(lon: float) -> Tuple[bool, int]:
    """Check if longitude indicates coastal (not far inland/offshore)."""
    if lon is None:
        return False, 0
    
    try:
        lon = float(lon)
    except (ValueError, TypeError):
        return False, 0
    
    # Optimal coastal range at 45N
    if OPTIMAL_LONGITUDE_MIN <= lon <= OPTIMAL_LONGITUDE_MAX:
        return True, 10  # Right on the coast
    elif LONGITUDE_MIN <= lon <= LONGITUDE_MAX:
        return True, 5   # In general area
    return False, 0


def verify_description_has_longitude(description: str) -> bool:
    """Check if description contains longitude information."""
    if not description:
        return False
    
    patterns = [
        r'-?\d+\.?\d*\s*[°]?\s*[WwEe]',          # e.g., 63.5°W or -63.5 W
        r'[Ll]ong[itude]*\s*[:=]?\s*-?\d+',       # e.g., longitude: -63.5
        r'-6[34]\.\d+',                           # Numeric longitude in expected range
        r'[Ll]on[g]?\s*[:=]?\s*-?\d+',           # e.g., lon: -63
        r'W\s*-?\d+\.?\d*',                       # W 63.5
    ]
    
    for pattern in patterns:
        if re.search(pattern, description, re.IGNORECASE):
            return True
    return False


def verify_in_region(lat: float, lon: float) -> Tuple[bool, int]:
    """Check if coordinates are in the general Atlantic Canada region."""
    try:
        lat = float(lat) if lat else 0
        lon = float(lon) if lon else 0
    except (ValueError, TypeError):
        return False, 0
    
    if (REGION_LATITUDE_MIN <= lat <= REGION_LATITUDE_MAX and 
        REGION_LONGITUDE_MIN <= lon <= REGION_LONGITUDE_MAX):
        return True, 15
    return False, 0


def query_vlm_safe(query_vlm, prompt: str, image=None, images=None) -> Dict:
    """Safely query VLM with error handling."""
    if not query_vlm:
        return {"success": False, "error": "VLM not available"}
    
    try:
        if images:
            result = query_vlm(prompt=prompt, images=images)
        elif image:
            result = query_vlm(prompt=prompt, image=image)
        else:
            return {"success": False, "error": "No images provided"}
        return result
    except Exception as e:
        logger.warning(f"VLM query failed: {e}")
        return {"success": False, "error": str(e)}


# ================================================================
# MAIN VERIFICATION FUNCTION
# ================================================================

def verify_lat_landfall_marking(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the lat_landfall_marking task.
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with copy_from_env function
        task_info: Task info with metadata
    
    Returns:
        dict with 'passed', 'score', 'feedback', 'details'
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available for verification",
            "details": {"error": "copy_from_env not provided"}
        }
    
    metadata = task_info.get('metadata', {})
    feedback_parts = []
    details = {}
    score = 0
    
    # ================================================================
    # STEP 1: Copy result JSON from container
    # ================================================================
    result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details['export_result'] = result
    except Exception as e:
        logger.warning(f"Failed to read task result: {e}")
        details['result_error'] = str(e)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # STEP 2: Anti-gaming - Check timing
    # ================================================================
    task_duration = result.get('task_duration_seconds', 0)
    if task_duration < 30:
        feedback_parts.append(f"⚠️ Task completed suspiciously fast ({task_duration}s)")
        details['timing_suspicious'] = True
    else:
        details['timing_suspicious'] = False
    
    # ================================================================
    # STEP 3: Copy and parse KML data
    # ================================================================
    placemark_data = {}
    temp_kml_data = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/placemark_data.json", temp_kml_data.name)
        with open(temp_kml_data.name, 'r') as f:
            placemark_data = json.load(f)
        details['placemark_data'] = placemark_data
    except Exception as e:
        logger.warning(f"Failed to read placemark data: {e}")
        details['placemark_parse_error'] = str(e)
    finally:
        if os.path.exists(temp_kml_data.name):
            os.unlink(temp_kml_data.name)
    
    # ================================================================
    # STEP 4: Verify placemark existence and name
    # ================================================================
    target_found = result.get('target_placemark_found', False) or placemark_data.get('target_found', False)
    target_data = placemark_data.get('target_data', {})
    
    if not target_data:
        # Fallback to result JSON data
        target_data = {
            'name': result.get('target_name', ''),
            'latitude': result.get('target_latitude', ''),
            'longitude': result.get('target_longitude', ''),
            'description': result.get('target_description', '')
        }
    
    # Check new placemarks were created
    new_placemarks = result.get('new_placemarks_created', 0)
    if new_placemarks > 0:
        details['new_placemarks'] = new_placemarks
    else:
        feedback_parts.append("⚠️ No new placemarks detected")
    
    if not target_found and not target_data.get('name'):
        feedback_parts.append("❌ Target placemark not found")
        details['target_found'] = False
    else:
        details['target_found'] = True
        details['target_data'] = target_data
    
    # ================================================================
    # CRITERION 1: Placemark name (10 points)
    # ================================================================
    name_ok, name_score = verify_placemark_name(target_data.get('name', ''))
    score += name_score
    details['name_score'] = name_score
    
    if name_score == 10:
        feedback_parts.append(f"✅ Correct placemark name: '{target_data.get('name')}'")
    elif name_score > 0:
        feedback_parts.append(f"⚠️ Partial name match: '{target_data.get('name')}'")
    else:
        feedback_parts.append("❌ Placemark name doesn't match expected pattern")
    
    # ================================================================
    # CRITERION 2: Latitude accuracy (25 points)
    # ================================================================
    lat = target_data.get('latitude')
    lat_ok, lat_score = verify_latitude(lat)
    score += lat_score
    details['latitude_score'] = lat_score
    details['latitude_value'] = lat
    details['latitude_accurate'] = lat_ok and lat_score >= 20
    
    if lat_score >= 25:
        feedback_parts.append(f"✅ Latitude accurate: {lat}° (target: 45.000°)")
    elif lat_score >= 20:
        feedback_parts.append(f"✅ Latitude close: {lat}° (target: 45.000°)")
    elif lat_score > 0:
        feedback_parts.append(f"⚠️ Latitude approximate: {lat}°")
    else:
        feedback_parts.append(f"❌ Latitude incorrect: {lat}° (target: 45.000°)")
    
    # ================================================================
    # CRITERION 3: Longitude validity (20 points)
    # ================================================================
    lon = target_data.get('longitude')
    lon_ok, lon_score = verify_longitude(lon)
    score += lon_score
    details['longitude_score'] = lon_score
    details['longitude_value'] = lon
    
    if lon_score >= 20:
        feedback_parts.append(f"✅ Longitude valid: {lon}° (Nova Scotia coast)")
    elif lon_score > 0:
        feedback_parts.append(f"⚠️ Longitude approximate: {lon}°")
    else:
        feedback_parts.append(f"❌ Longitude invalid: {lon}° (expected -64.5 to -63.0)")
    
    # ================================================================
    # CRITERION 4: Description has longitude (10 points)
    # ================================================================
    description = target_data.get('description', '')
    desc_ok = verify_description_has_longitude(description)
    if desc_ok:
        score += 10
        feedback_parts.append("✅ Description documents longitude")
        details['description_score'] = 10
    else:
        feedback_parts.append("❌ Description missing longitude")
        details['description_score'] = 0
    
    # ================================================================
    # CRITERION 5: Navigation to correct region (15 points)
    # ================================================================
    region_ok, region_score = verify_in_region(lat, lon)
    score += region_score
    details['region_score'] = region_score
    
    if region_score > 0:
        feedback_parts.append("✅ Navigated to correct region (Atlantic Canada)")
    else:
        feedback_parts.append("❌ Not in expected region")
    
    # ================================================================
    # CRITERION 6: Coastal positioning (10 points)
    # ================================================================
    coastal_ok, coastal_score = verify_coastal_position(lon)
    score += coastal_score
    details['coastal_score'] = coastal_score
    
    if coastal_score >= 10:
        feedback_parts.append("✅ Placemark at coastline")
    elif coastal_score > 0:
        feedback_parts.append("⚠️ Placemark near coast")
    else:
        feedback_parts.append("❌ Placemark not at coast")
    
    # ================================================================
    # CRITERION 7: VLM Trajectory Verification (10 points)
    # ================================================================
    vlm_score = 0
    
    if query_vlm:
        # Get trajectory frames
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=5)
            final_screenshot = get_final_screenshot(traj)
        except ImportError:
            frames = []
            final_screenshot = None
            logger.warning("Could not import VLM utilities")
        
        # Verify trajectory
        if frames and len(frames) >= 2:
            traj_result = query_vlm_safe(query_vlm, TRAJECTORY_VERIFICATION_PROMPT, images=frames)
            
            if traj_result.get('success'):
                parsed = traj_result.get('parsed', {})
                details['vlm_trajectory'] = parsed
                
                criteria_met = sum([
                    parsed.get('grid_visible', False),
                    parsed.get('nova_scotia_visible', False),
                    parsed.get('placemark_creation_visible', False),
                    parsed.get('workflow_progression', False),
                    parsed.get('coastal_navigation', False)
                ])
                
                if criteria_met >= 4:
                    vlm_score = 10
                    feedback_parts.append("✅ VLM: Workflow verified (grid, navigation, placemark)")
                elif criteria_met >= 2:
                    vlm_score = 5
                    feedback_parts.append("⚠️ VLM: Partial workflow verified")
                else:
                    feedback_parts.append("❌ VLM: Workflow not verified")
            else:
                feedback_parts.append("⚠️ VLM trajectory verification failed")
        else:
            feedback_parts.append("⚠️ Insufficient trajectory frames for VLM")
        
        # Also check final state
        if final_screenshot:
            final_result = query_vlm_safe(query_vlm, FINAL_STATE_PROMPT, image=final_screenshot)
            if final_result.get('success'):
                details['vlm_final'] = final_result.get('parsed', {})
    else:
        # Give benefit of doubt if VLM not available
        vlm_score = 5
        feedback_parts.append("⚠️ VLM not available, partial credit given")
    
    score += vlm_score
    details['vlm_score'] = vlm_score
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    details['total_score'] = score
    details['max_score'] = 100
    
    # Pass criteria: 70+ points AND latitude is accurate
    latitude_accurate = details.get('latitude_accurate', False)
    passed = score >= 70 and latitude_accurate
    
    if passed:
        feedback_parts.insert(0, f"✅ PASSED ({score}/100 points)")
    else:
        if not latitude_accurate:
            feedback_parts.insert(0, f"❌ FAILED ({score}/100 points) - Latitude not accurate")
        else:
            feedback_parts.insert(0, f"❌ FAILED ({score}/100 points) - Below threshold")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }