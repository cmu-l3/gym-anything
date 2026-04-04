#!/usr/bin/env python3
"""
Verifier for River Confluence Marking task.

VERIFICATION STRATEGY:
1. Placemark exists with correct name (20 points)
2. File was created/modified during task - anti-gaming (10 points)
3. Placemark coordinates within 5km of confluence (25 points)
4. High precision placement within 1km (20 points bonus)
5. Description contains coordinate information (15 points)
6. VLM trajectory verification - shows river navigation (10 points)

Pass threshold: 65 points minimum with placemark existence and correct region required.

Ground Truth:
- Ohio-Mississippi Confluence: 36.9871°N, 89.1328°W
- Located at southern tip of Illinois near Cairo
- Fort Defiance State Park marks the confluence point
"""

import json
import tempfile
import os
import math
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ground truth coordinates
CONFLUENCE_LAT = 36.9871
CONFLUENCE_LON = -89.1328
TOLERANCE_KM_PASS = 5.0
TOLERANCE_KM_BONUS = 1.0

EXPECTED_NAME_KEYWORDS = ['ohio', 'mississippi', 'confluence']


def haversine_distance(lat1, lon1, lat2, lon2):
    """Calculate distance in km between two lat/lon points using Haversine formula."""
    R = 6371  # Earth's radius in km
    
    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    delta_lat = math.radians(lat2 - lat1)
    delta_lon = math.radians(lon2 - lon1)
    
    a = math.sin(delta_lat/2)**2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(delta_lon/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    
    return R * c


def check_name_matches(name):
    """Check if placemark name contains required keywords."""
    if not name:
        return False
    name_lower = name.lower()
    return all(keyword in name_lower for keyword in EXPECTED_NAME_KEYWORDS)


def check_description_has_coords(description):
    """Check if description contains coordinate information."""
    if not description:
        return False
    
    # Look for various coordinate patterns
    patterns = [
        r'\d{1,3}\.\d+',           # Decimal degrees like 36.98
        r'\d{1,3}°',               # Degree symbol
        r'[Ll]at(itude)?',         # "latitude" or "lat"
        r'[Ll]on(gitude)?',        # "longitude" or "lon"
        r'[Cc]oord',               # "coordinates"
        r'\d+°\s*\d+\'',           # DMS format like 36° 59'
        r'[NS]\s*\d+',             # N/S notation
        r'[EW]\s*\d+',             # E/W notation
    ]
    
    for pattern in patterns:
        if re.search(pattern, description):
            return True
    return False


def verify_via_vlm(traj, query_vlm):
    """Use VLM to verify trajectory shows river confluence navigation."""
    if not query_vlm:
        return {"success": False, "score": 0, "error": "VLM not available"}
    
    # Import trajectory frame sampling
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Get trajectory frames (sample across the episode)
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        if final and final not in frames:
            frames.append(final)
        
        if not frames:
            return {"success": False, "score": 0, "error": "No trajectory frames available"}
        
    except ImportError:
        # Fallback if import fails
        frames = traj.get('frames', [])[-5:] if traj.get('frames') else []
        if not frames:
            return {"success": False, "score": 0, "error": "Could not get trajectory frames"}
    
    # VLM prompt for trajectory verification
    prompt = """You are analyzing screenshots from an agent performing a geographic task in Google Earth.

TASK: Navigate to the confluence of the Ohio River and Mississippi River near Cairo, Illinois, and create a placemark.

Analyze these trajectory screenshots (shown chronologically) and determine:

1. GOOGLE_EARTH_VISIBLE: Is Google Earth Pro visible in any of the screenshots?
2. RIVER_NAVIGATION: Do the screenshots show navigation to a river confluence area (two rivers meeting)?
3. ILLINOIS_REGION: Does the view show the Illinois/Kentucky/Missouri border region (southern Illinois)?
4. PLACEMARK_CREATION: Is there evidence of a placemark being created (placemark dialog, pin visible)?
5. CONFLUENCE_VISIBLE: Can you see where two large rivers meet (Y-shaped junction)?

The Ohio-Mississippi confluence is where the Ohio River joins the Mississippi River at the southern tip of Illinois. The rivers create a distinctive Y-shape where they meet.

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "river_navigation": true/false,
    "illinois_region": true/false,
    "placemark_creation": true/false,
    "confluence_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see in the trajectory"
}
"""
    
    try:
        result = query_vlm(prompt=prompt, images=frames)
        
        if not result.get("success"):
            return {"success": False, "score": 0, "error": result.get("error", "VLM query failed")}
        
        parsed = result.get("parsed", {})
        
        # Calculate VLM score
        criteria_met = sum([
            parsed.get("google_earth_visible", False),
            parsed.get("river_navigation", False),
            parsed.get("illinois_region", False),
            parsed.get("placemark_creation", False),
            parsed.get("confluence_visible", False),
        ])
        
        confidence = parsed.get("confidence", "low")
        confidence_multiplier = {"high": 1.0, "medium": 0.8, "low": 0.6}.get(confidence, 0.6)
        
        # Max 10 points for VLM, scaled by criteria and confidence
        vlm_score = int((criteria_met / 5) * 10 * confidence_multiplier)
        
        return {
            "success": True,
            "score": vlm_score,
            "criteria_met": criteria_met,
            "confidence": confidence,
            "details": parsed
        }
        
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        return {"success": False, "score": 0, "error": str(e)}


def verify_river_confluence_marking(traj, env_info, task_info):
    """
    Verify that the agent created a correctly placed placemark at the river confluence.
    
    Multi-signal verification:
    1. Programmatic: Check placemark in myplaces.kml
    2. Anti-gaming: Verify file was modified during task
    3. Location: Validate coordinates against ground truth
    4. VLM: Trajectory verification showing actual work
    
    Args:
        traj: Trajectory data with frames
        env_info: Environment info with copy_from_env and query_vlm
        task_info: Task metadata
    
    Returns:
        dict with 'passed', 'score', 'feedback', 'details'
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available",
            "details": {}
        }
    
    # Get task metadata
    metadata = task_info.get('metadata', {})
    expected_lat = metadata.get('confluence_lat', CONFLUENCE_LAT)
    expected_lon = metadata.get('confluence_lon', CONFLUENCE_LON)
    tolerance_pass = metadata.get('tolerance_km_pass', TOLERANCE_KM_PASS)
    tolerance_bonus = metadata.get('tolerance_km_bonus', TOLERANCE_KM_BONUS)
    
    feedback_parts = []
    score = 0
    details = {}
    
    print("=" * 60)
    print("River Confluence Marking - Verification")
    print("=" * 60)
    
    # ================================================================
    # Copy result file from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details['export_result'] = result
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to read task result: {e}",
            "details": details
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: Placemark exists with correct name (20 points)
    # ================================================================
    placemark_found = result.get('placemark_found', False)
    placemark_name = result.get('placemark_name', '')
    
    if placemark_found and check_name_matches(placemark_name):
        score += 20
        feedback_parts.append(f"✅ Placemark found: '{placemark_name}' (+20)")
        details['placemark_exists'] = True
        details['placemark_name'] = placemark_name
    elif placemark_found:
        score += 10
        feedback_parts.append(f"⚠️ Placemark found but name may not match: '{placemark_name}' (+10)")
        details['placemark_exists'] = True
        details['placemark_name'] = placemark_name
    else:
        feedback_parts.append("❌ Placemark 'Ohio-Mississippi Confluence' not found")
        details['placemark_exists'] = False
        # Cannot continue without placemark
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: File was created/modified during task (10 points)
    # ================================================================
    file_created = result.get('file_created', False)
    file_modified = result.get('file_modified', False)
    
    if file_created:
        score += 10
        feedback_parts.append("✅ myplaces.kml newly created during task (+10)")
        details['file_modified_during_task'] = True
    elif file_modified:
        score += 10
        feedback_parts.append("✅ myplaces.kml modified during task (+10)")
        details['file_modified_during_task'] = True
    else:
        feedback_parts.append("⚠️ myplaces.kml not modified during task window")
        details['file_modified_during_task'] = False
    
    # ================================================================
    # CRITERION 3: Placemark coordinates within 5km of confluence (25 points)
    # ================================================================
    placemark_lat = result.get('placemark_lat', 0)
    placemark_lon = result.get('placemark_lon', 0)
    
    if placemark_lat != 0 and placemark_lon != 0:
        distance_km = haversine_distance(placemark_lat, placemark_lon, expected_lat, expected_lon)
        details['placemark_lat'] = placemark_lat
        details['placemark_lon'] = placemark_lon
        details['distance_km'] = distance_km
        
        print(f"  Placemark coordinates: {placemark_lat:.4f}°N, {abs(placemark_lon):.4f}°W")
        print(f"  Expected coordinates: {expected_lat:.4f}°N, {abs(expected_lon):.4f}°W")
        print(f"  Distance from confluence: {distance_km:.2f} km")
        
        if distance_km <= tolerance_pass:
            score += 25
            feedback_parts.append(f"✅ Placemark within {tolerance_pass}km of confluence ({distance_km:.1f}km) (+25)")
            details['in_correct_region'] = True
            
            # ================================================================
            # CRITERION 4: High precision placement within 1km (20 points bonus)
            # ================================================================
            if distance_km <= tolerance_bonus:
                score += 20
                feedback_parts.append(f"✅ High precision: within {tolerance_bonus}km ({distance_km:.2f}km) (+20)")
                details['high_precision'] = True
            else:
                feedback_parts.append(f"○ Not within {tolerance_bonus}km for precision bonus ({distance_km:.2f}km)")
                details['high_precision'] = False
        else:
            feedback_parts.append(f"❌ Placemark too far from confluence ({distance_km:.1f}km > {tolerance_pass}km)")
            details['in_correct_region'] = False
    else:
        feedback_parts.append("❌ Could not parse placemark coordinates")
        details['in_correct_region'] = False
    
    # ================================================================
    # CRITERION 5: Description contains coordinate information (15 points)
    # ================================================================
    placemark_description = result.get('placemark_description', '')
    details['placemark_description'] = placemark_description
    
    if check_description_has_coords(placemark_description):
        score += 15
        feedback_parts.append("✅ Description contains coordinate information (+15)")
        details['description_has_coords'] = True
    else:
        feedback_parts.append("○ Description does not contain coordinate information")
        details['description_has_coords'] = False
    
    # ================================================================
    # CRITERION 6: VLM trajectory verification (10 points)
    # ================================================================
    vlm_result = verify_via_vlm(traj, query_vlm)
    details['vlm_verification'] = vlm_result
    
    if vlm_result.get('success'):
        vlm_score = vlm_result.get('score', 0)
        score += vlm_score
        criteria_met = vlm_result.get('criteria_met', 0)
        feedback_parts.append(f"✅ VLM trajectory verification ({criteria_met}/5 criteria) (+{vlm_score})")
    else:
        feedback_parts.append(f"○ VLM verification skipped: {vlm_result.get('error', 'unavailable')}")
    
    # ================================================================
    # Final assessment
    # ================================================================
    print("\n" + "=" * 60)
    print(f"Final Score: {score}/100")
    
    # Pass requirements:
    # - Score >= 65
    # - Placemark must exist
    # - Must be in correct region (within 5km)
    placemark_ok = details.get('placemark_exists', False)
    region_ok = details.get('in_correct_region', False)
    
    passed = score >= 65 and placemark_ok and region_ok
    
    if passed:
        print("Result: PASS ✅")
    else:
        print("Result: FAIL ❌")
        if not placemark_ok:
            print("  (Required: Placemark must exist with correct name)")
        if not region_ok:
            print("  (Required: Placemark must be within 5km of confluence)")
        if score < 65:
            print(f"  (Required: Score must be >= 65, got {score})")
    
    print("=" * 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }


if __name__ == "__main__":
    # Test mode - for local debugging
    print("River Confluence Marking Verifier")
    print("Run via gym-anything framework for full verification")